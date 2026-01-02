// lib/core/security/vault_crypto_context.dart
//
// Captures encryption-at-rest state for the mounted vault.
//
// States:
// - Unencrypted:     isEncrypted=false, info/service/key all null
// - Encrypted locked: isEncrypted=true,  info/service set, key=null, isLocked=true
// - Encrypted unlocked: isEncrypted=true, info/service set, key!=null, isLocked=false

import 'package:thpitze_main/core/security/vault_crypto_models.dart';
import 'package:thpitze_main/core/security/vault_encryption_service.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';

class VaultCryptoContext {
  final bool isEncrypted;
  final bool isLocked;

  /// Present if encryption metadata exists / encryption is enabled.
  final VaultEncryptionInfo? info;

  /// Present when encryption is supported/configured.
  final VaultEncryptionService? encryptionService;

  /// Present only when unlocked (derived + verified).
  final VaultKey? key;

  const VaultCryptoContext._({
    required this.isEncrypted,
    required this.isLocked,
    required this.info,
    required this.encryptionService,
    required this.key,
  });

  /// No encryption-at-rest.
  const VaultCryptoContext.unencrypted()
      : this._(
          isEncrypted: false,
          isLocked: false,
          info: null,
          encryptionService: null,
          key: null,
        );

  /// Encryption enabled but credentials/key not available or not verified.
  const VaultCryptoContext.encryptedLocked({
    required VaultEncryptionInfo info,
    required VaultEncryptionService encryptionService,
  }) : this._(
          isEncrypted: true,
          isLocked: true,
          info: info,
          encryptionService: encryptionService,
          key: null,
        );

  /// Encryption enabled and key has been verified.
  const VaultCryptoContext.encryptedUnlocked({
    required VaultEncryptionInfo info,
    required VaultEncryptionService encryptionService,
    required VaultKey key,
  }) : this._(
          isEncrypted: true,
          isLocked: false,
          info: info,
          encryptionService: encryptionService,
          key: key,
        );

  VaultEncryptionInfo get requireInfo {
    final v = info;
    if (v == null) {
      throw StateError('Vault is not encrypted; no VaultEncryptionInfo available.');
    }
    return v;
  }

  VaultEncryptionService get requireEncryptionService {
    final s = encryptionService;
    if (s == null) {
      throw StateError('Vault is not encrypted; no VaultEncryptionService available.');
    }
    return s;
  }

  VaultKey get requireKey {
    final k = key;
    if (k == null) {
      throw StateError('Vault is locked; no derived key available.');
    }
    return k;
  }
}
