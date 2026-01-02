// lib/core/vault/vault_errors.dart
//
// Core-level, typed vault failures.
// These types are intentionally UI-agnostic and are used by the App layer to
// distinguish recoverable auth states from structural vault failures.

class VaultException implements Exception {
  final String message;
  VaultException(this.message);

  @override
  String toString() => 'VaultException: $message';
}

/// Vault identity could not be located (e.g. missing vault.json).
class VaultNotFoundException extends VaultException {
  VaultNotFoundException(String message) : super(message);
}

/// Vault contents are structurally invalid/corrupt/unreadable.
/// This is NOT an authentication failure.
class VaultCorruptException extends VaultException {
  VaultCorruptException(String message) : super(message);
}

/// Vault exists but uses a schema/version the current Core does not support.
class VersionUnsupportedException extends VaultException {
  final int? foundSchemaVersion;
  final int? expectedSchemaVersion;

  VersionUnsupportedException(
    String message, {
    this.foundSchemaVersion,
    this.expectedSchemaVersion,
  }) : super(message);
}

/// Vault is protected and requires credentials (host must prompt user).
class AuthRequiredException extends VaultException {
  AuthRequiredException(String message) : super(message);
}

/// Credentials were provided but are invalid.
class InvalidCredentialsException extends VaultException {
  InvalidCredentialsException(String message) : super(message);
}

/// Backwards-compat alias for earlier code that used "invalid" for structural failures.
/// Prefer [VaultCorruptException] or [VersionUnsupportedException] in new code.
class VaultInvalidException extends VaultCorruptException {
  VaultInvalidException(String message) : super(message);
}
