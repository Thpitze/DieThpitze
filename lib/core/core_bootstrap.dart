import 'dart:io';

import 'package:thpitze_main/core/core_context.dart';
import 'package:thpitze_main/core/security/vault_crypto_context.dart';
import 'package:thpitze_main/core/security/vault_encryption_service_impl.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_auth_service.dart';
import 'package:thpitze_main/core/vault/vault_encryption_metadata_service.dart';
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
  }) : vaultAuthService = vaultAuthService ?? const VaultAuthService(),
       vaultEncryptionMetadataService =
           vaultEncryptionMetadataService ?? VaultEncryptionMetadataService();

  CoreContext openVault(Directory vaultRoot, {String? password}) {
    final info = vaultIdentityService.readVaultInfo(vaultRoot);

    // Password-auth (auth.json)
    vaultAuthService.requireAuth(
      vaultRoot: vaultRoot,
      vaultId: info.vaultId,
      password: password,
    );

    // Encryption-at-rest metadata (encryption.json). For now: populate context,
    // but keep key null unless/until you implement unlock flow here.
    final encInfo = vaultEncryptionMetadataService.loadOrDefault(
      vaultRoot: vaultRoot,
    );

    final crypto = encInfo.isEnabled
        ? VaultCryptoContext.encryptedLocked(
            info: encInfo,
            encryptionService: VaultEncryptionServiceImpl(),
          )
        : const VaultCryptoContext.unencrypted();

    return CoreContext(
      vaultRoot: vaultRoot,
      vaultInfo: info,
      crypto: crypto,
      clock: clock,
    );
  }
}
