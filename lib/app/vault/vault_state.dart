/* lib/app/vault/vault_state.dart */

enum VaultStateKind { closed, opening, open, locked, error }

class VaultState {
  final VaultStateKind kind;
  final String? vaultPath;

  // Error only
  final String? errorMessage;

  // Locked only (manual|timeout|unknown)
  final String? lockReason;

  const VaultState._({
    required this.kind,
    required this.vaultPath,
    required this.errorMessage,
    required this.lockReason,
  });

  const VaultState.closed()
    : this._(
        kind: VaultStateKind.closed,
        vaultPath: null,
        errorMessage: null,
        lockReason: null,
      );

  const VaultState.opening(String path)
    : this._(
        kind: VaultStateKind.opening,
        vaultPath: path,
        errorMessage: null,
        lockReason: null,
      );

  const VaultState.open(String path)
    : this._(
        kind: VaultStateKind.open,
        vaultPath: path,
        errorMessage: null,
        lockReason: null,
      );

  const VaultState.locked(String path, {String reason = 'unknown'})
    : this._(
        kind: VaultStateKind.locked,
        vaultPath: path,
        errorMessage: null,
        lockReason: reason,
      );

  const VaultState.error(String path, String message)
    : this._(
        kind: VaultStateKind.error,
        vaultPath: path,
        errorMessage: message,
        lockReason: null,
      );

  bool get isOpen => kind == VaultStateKind.open;
  bool get isClosed => kind == VaultStateKind.closed;
  bool get isLocked => kind == VaultStateKind.locked;
}
