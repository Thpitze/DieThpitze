/* lib/app/vault/vault_dashboard_controller.dart */
import 'package:flutter/foundation.dart';

import '../core_adapter_impl.dart';
import 'vault_controller.dart';

class VaultDashboardSnapshot {
  final bool hasVaultOpen;
  final String? vaultPath;

  final int? recordCount;
  final DateTime? lastRefreshUtc;

  final String? lastError;

  const VaultDashboardSnapshot({
    required this.hasVaultOpen,
    required this.vaultPath,
    required this.recordCount,
    required this.lastRefreshUtc,
    required this.lastError,
  });

  factory VaultDashboardSnapshot.initial({required bool hasVaultOpen, required String? vaultPath}) {
    return VaultDashboardSnapshot(
      hasVaultOpen: hasVaultOpen,
      vaultPath: vaultPath,
      recordCount: null,
      lastRefreshUtc: null,
      lastError: null,
    );
  }

  VaultDashboardSnapshot copyWith({
    bool? hasVaultOpen,
    String? vaultPath,
    int? recordCount,
    DateTime? lastRefreshUtc,
    String? lastError,
    bool clearError = false,
    bool clearCounts = false,
  }) {
    return VaultDashboardSnapshot(
      hasVaultOpen: hasVaultOpen ?? this.hasVaultOpen,
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
  })  : _adapter = adapter,
        _vault = vault,
        _snap = VaultDashboardSnapshot.initial(
          hasVaultOpen: vault.state.isOpen,
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
    final isOpen = _vault.state.isOpen;
    final path = _vault.state.vaultPath;

    // On close: clear counts to avoid stale display.
    if (!isOpen) {
      _snap = _snap.copyWith(
        hasVaultOpen: false,
        vaultPath: null,
        clearCounts: true,
        clearError: true,
      );
      notifyListeners();
      return;
    }

    // On open: update state and optionally auto-refresh.
    _snap = _snap.copyWith(
      hasVaultOpen: true,
      vaultPath: path,
      clearError: true,
    );
    notifyListeners();

    // Best-effort refresh (don’t await here; UI remains responsive)
    refreshCounts();
  }

  Future<void> refreshCounts() async {
    if (!_vault.state.isOpen) return;

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
