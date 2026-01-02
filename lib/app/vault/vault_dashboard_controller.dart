/* lib/app/vault/vault_dashboard_controller.dart */
import 'package:flutter/foundation.dart';

import '../core_adapter_impl.dart';
import 'vault_controller.dart';
import 'vault_state.dart';

class VaultDashboardSnapshot {
  final VaultStateKind vaultKind;
  final String? vaultPath;

  final int? recordCount;
  final DateTime? lastRefreshUtc;

  final String? lastError;

  const VaultDashboardSnapshot({
    required this.vaultKind,
    required this.vaultPath,
    required this.recordCount,
    required this.lastRefreshUtc,
    required this.lastError,
  });

  bool get hasVaultOpen => vaultKind == VaultStateKind.open;
  bool get isLocked => vaultKind == VaultStateKind.locked;

  factory VaultDashboardSnapshot.initial({
    required VaultStateKind kind,
    required String? vaultPath,
  }) {
    return VaultDashboardSnapshot(
      vaultKind: kind,
      vaultPath: vaultPath,
      recordCount: null,
      lastRefreshUtc: null,
      lastError: null,
    );
  }

  VaultDashboardSnapshot copyWith({
    VaultStateKind? vaultKind,
    String? vaultPath,
    int? recordCount,
    DateTime? lastRefreshUtc,
    String? lastError,
    bool clearError = false,
    bool clearCounts = false,
  }) {
    return VaultDashboardSnapshot(
      vaultKind: vaultKind ?? this.vaultKind,
      vaultPath: vaultPath ?? this.vaultPath,
      recordCount: clearCounts ? null : (recordCount ?? this.recordCount),
      lastRefreshUtc: lastRefreshUtc ?? this.lastRefreshUtc,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class VaultDashboardController extends ChangeNotifier {
  final CoreAdapterImpl _adapter;
  final VaultController _vault;

  VaultDashboardSnapshot _snap;

  VaultDashboardController({
    required CoreAdapterImpl adapter,
    required VaultController vault,
  }) : _adapter = adapter,
       _vault = vault,
       _snap = VaultDashboardSnapshot.initial(
         kind: vault.state.kind,
         vaultPath: vault.state.vaultPath,
       ) {
    _vault.addListener(_onVaultStateChanged);
  }

  VaultDashboardSnapshot get snap => _snap;

  void disposeController() {
    _vault.removeListener(_onVaultStateChanged);
    dispose();
  }

  void _onVaultStateChanged() {
    final kind = _vault.state.kind;
    final path = _vault.state.vaultPath;

    // Closed / Error: clear counts and path to avoid stale display.
    if (kind == VaultStateKind.closed || kind == VaultStateKind.error) {
      _snap = _snap.copyWith(
        vaultKind: kind,
        vaultPath: null,
        clearCounts: true,
        clearError: true,
      );
      notifyListeners();
      return;
    }

    // Locked: keep path visible, but do not refresh counts.
    if (kind == VaultStateKind.locked) {
      _snap = _snap.copyWith(
        vaultKind: kind,
        vaultPath: path,
        clearError: true,
      );
      notifyListeners();
      return;
    }

    // Opening: show path, clear counts (avoid lying).
    if (kind == VaultStateKind.opening) {
      _snap = _snap.copyWith(
        vaultKind: kind,
        vaultPath: path,
        clearCounts: true,
        clearError: true,
      );
      notifyListeners();
      return;
    }

    // Open: update state and optionally auto-refresh.
    _snap = _snap.copyWith(vaultKind: kind, vaultPath: path, clearError: true);
    notifyListeners();

    // Best-effort refresh (don’t await here; UI remains responsive)
    refreshCounts();
  }

  Future<void> refreshCounts() async {
    if (_vault.state.kind != VaultStateKind.open) return;

    try {
      final items = await _adapter.listRecords();
      _snap = _snap.copyWith(
        recordCount: items.length,
        lastRefreshUtc: DateTime.now().toUtc(),
        clearError: true,
      );
      notifyListeners();
    } catch (e) {
      _snap = _snap.copyWith(
        lastError: e.toString(),
        lastRefreshUtc: DateTime.now().toUtc(),
      );
      notifyListeners();
    }
  }
}
