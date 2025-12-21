// lib/core/vault/vault_errors.dart
class VaultException implements Exception {
  final String message;
  VaultException(this.message);

  @override
  String toString() => 'VaultException: $message';
}

class VaultNotFoundException extends VaultException {
  VaultNotFoundException(String message) : super(message);
}

class VaultInvalidException extends VaultException {
  VaultInvalidException(String message) : super(message);
}
