// lib/core/security/vault_crypto_models.dart
//
// P19.1: Crypto contract models (no implementation yet).
// Defines payload layout and error types used by encryption-at-rest.
//
// IMPORTANT: Wrong key => Locked semantics. Corrupt data => Error semantics.

import 'dart:typed_data';

/// Derived key material for vault encryption.
/// Implementation will decide how to derive and store this in memory.
/// No disk persistence.
class VaultKey {
  final Uint8List bytes;
  const VaultKey(this.bytes);
}

/// AEAD payload representation.
/// This is intentionally explicit (nonce/tag separated) to avoid ambiguity.
class EncryptedPayload {
  final Uint8List nonce; // 12 bytes recommended for GCM
  final Uint8List ciphertext;
  final Uint8List tag; // 16 bytes typical for GCM

  const EncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });
}

/// Thrown when decryption fails due to wrong credentials / wrong key.
/// Must map to "Locked" in the host error model.
class VaultCryptoLocked implements Exception {
  final String message;
  const VaultCryptoLocked([
    this.message = 'Invalid credentials for encrypted vault',
  ]);
  @override
  String toString() => 'VaultCryptoLocked: $message';
}

/// Thrown when ciphertext is corrupted / malformed / auth tag invalid for reasons
/// that indicate data corruption, not just a wrong password.
/// Must map to "Error" in the host error model.
class VaultCryptoCorrupt implements Exception {
  final String message;
  const VaultCryptoCorrupt([this.message = 'Encrypted vault data is corrupt']);
  @override
  String toString() => 'VaultCryptoCorrupt: $message';
}

/// Thrown if encryption is requested but unsupported version/parameters are encountered.
class VaultCryptoUnsupported implements Exception {
  final String message;
  const VaultCryptoUnsupported(this.message);
  @override
  String toString() => 'VaultCryptoUnsupported: $message';
}
