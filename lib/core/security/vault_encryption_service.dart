// lib/core/security/vault_encryption_service.dart
//
// P19.2: Encryption service contract (async).
// Real implementation uses cryptography (async API).

import 'dart:typed_data';

import 'package:thpitze_main/core/security/vault_crypto_models.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';

abstract class VaultEncryptionService {
  Future<VaultKey> deriveKey({
    required VaultEncryptionInfo info,
    required String password,
    required Uint8List salt,
  });

  Future<EncryptedPayload> encrypt({
    required VaultEncryptionInfo info,
    required VaultKey key,
    required Uint8List plaintext,
    Uint8List? aad,
  });

  Future<Uint8List> decrypt({
    required VaultEncryptionInfo info,
    required VaultKey key,
    required EncryptedPayload payload,
    Uint8List? aad,
  });
}

/// Stub implementation used until a real implementation is injected.
class VaultEncryptionServiceStub implements VaultEncryptionService {
  @override
  Future<VaultKey> deriveKey({
    required VaultEncryptionInfo info,
    required String password,
    required Uint8List salt,
  }) async {
    throw const VaultCryptoUnsupported(
      'Vault encryption is not implemented yet',
    );
  }

  @override
  Future<EncryptedPayload> encrypt({
    required VaultEncryptionInfo info,
    required VaultKey key,
    required Uint8List plaintext,
    Uint8List? aad,
  }) async {
    throw const VaultCryptoUnsupported(
      'Vault encryption is not implemented yet',
    );
  }

  @override
  Future<Uint8List> decrypt({
    required VaultEncryptionInfo info,
    required VaultKey key,
    required EncryptedPayload payload,
    Uint8List? aad,
  }) async {
    throw const VaultCryptoUnsupported(
      'Vault encryption is not implemented yet',
    );
  }
}
