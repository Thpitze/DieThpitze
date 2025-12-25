/* lib/app/vault/vault_state.dart */

enum VaultStateKind { closed, opening, open, error }

class VaultState {
  final VaultStateKind kind;
  final String? vaultPath;
  final String? errorMessage;

  const VaultState._({
    required this.kind,
    required this.vaultPath,
    required this.errorMessage,
  });

  const VaultState.closed() : this._(kind: VaultStateKind.closed, vaultPath: null, errorMessage: null);

  const VaultState.opening(String path)
      : this._(kind: VaultStateKind.opening, vaultPath: path, errorMessage: null);

  const VaultState.open(String path) : this._(kind: VaultStateKind.open, vaultPath: path, errorMessage: null);

  const VaultState.error(String path, String message)
      : this._(kind: VaultStateKind.error, vaultPath: path, errorMessage: message);

  bool get isOpen => kind == VaultStateKind.open;
  bool get isClosed => kind == VaultStateKind.closed;
}
