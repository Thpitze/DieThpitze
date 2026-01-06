import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:thpitze_main/core/core_context.dart';
import 'package:thpitze_main/core/security/vault_crypto_context.dart';
import 'package:thpitze_main/core/security/vault_crypto_models.dart';
import 'package:thpitze_main/core/security/vault_encryption_service_impl.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_auth_service.dart';
import 'package:thpitze_main/core/vault/vault_encryption_metadata_service.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';
import 'package:thpitze_main/core/vault/vault_identity_service.dart';

class CoreBootstrap {
  final VaultIdentityService vaultIdentityService;
  final VaultAuthService vaultAuthService;
  final VaultEncryptionMetadataService vaultEncryptionMetadataService;
  final Clock clock;

  CoreBootstrap({
    required this.vaultIdentityService,
    required this.clock,
    VaultAuthService? vaultAuthService,
    VaultEncryptionMetadataService? vaultEncryptionMetadataService,
  })  : vaultAuthService = vaultAuthService ?? const VaultAuthService(),
        vaultEncryptionMetadataService =
            vaultEncryptionMetadataService ?? VaultEncryptionMetadataService();

  /// Open a vault and fully resolve auth + encryption state.
  ///
  /// Rules:
  /// - auth.json present => requires password (VaultAuthService.requireAuth handles this)
  /// - encryption.json enabled => requires password to unlock crypto key
  ///     missing password => AuthRequiredException('encryption_required')
  ///     wrong password => InvalidCredentialsException('Invalid credentials for encrypted vault')
  Future<CoreContext> openVault(Directory vaultRoot, {String? password}) async {
    final info = vaultIdentityService.readVaultInfo(vaultRoot);

    // Password-auth (auth.json)
    vaultAuthService.requireAuth(
      vaultRoot: vaultRoot,
      vaultId: info.vaultId,
      password: password,
    );

    // Encryption-at-rest metadata (encryption.json)
    final encInfo = vaultEncryptionMetadataService.loadOrDefault(
      vaultRoot: vaultRoot,
    );

    // Default crypto context
    if (!encInfo.isEnabled) {
      return CoreContext(
        vaultRoot: vaultRoot,
        vaultInfo: info,
        crypto: const VaultCryptoContext.unencrypted(),
        clock: clock,
      );
    }

    // Encrypted vault: require password to derive+verify key.
    final pw = (password ?? '').trim();
    if (pw.isEmpty) {
      // Important: allow host/UI to distinguish why it is locked.
      throw AuthRequiredException('encryption_required');
    }

    final encSvc = VaultEncryptionServiceImpl();

    try {
      final saltB64 = (encInfo.saltB64 ?? '').trim();
      if (saltB64.isEmpty) {
        throw VaultCorruptException('Missing saltB64 in encryption metadata');
      }

      final Uint8List salt = Uint8List.fromList(base64Decode(saltB64));

      final key = await encSvc.deriveKey(
        info: encInfo,
        password: pw,
        salt: salt,
      );

      await encSvc.verifyKeyCheckB64(info: encInfo, key: key);

      final crypto = VaultCryptoContext.encryptedUnlocked(
        info: encInfo,
        encryptionService: encSvc,
        key: key,
      );

      return CoreContext(
        vaultRoot: vaultRoot,
        vaultInfo: info,
        crypto: crypto,
        clock: clock,
      );
    } on VaultCryptoLocked {
      throw InvalidCredentialsException('Invalid credentials for encrypted vault');
    } on VaultCryptoUnsupported catch (e) {
      // Treat unsupported metadata as structural/corrupt for now.
      throw VaultCorruptException(e.message);
    } on VaultCryptoCorrupt catch (e) {
      throw VaultCorruptException(e.message);
    }
  }
}
