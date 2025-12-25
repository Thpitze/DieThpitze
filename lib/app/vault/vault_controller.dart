/* lib/app/vault/vault_controller.dart */
import 'package:flutter/foundation.dart';

import '../events/app_event_bus.dart';
import '../events/vault_events.dart';
import '../events/working_memory.dart';
import '../settings/app_settings.dart';
import '../core_adapter_impl.dart';
import 'vault_state.dart';

class VaultController extends ChangeNotifier {
  final CoreAdapterImpl _adapter;
  final WorkingMemory _workingMemory;
  final AppEventBus _eventBus;
  final AppSettingsStore _settingsStore;

  VaultState _state = const VaultState.closed();
  AppSettings _settings = AppSettings.defaults();

  VaultController({
    required CoreAdapterImpl adapter,
    required WorkingMemory workingMemory,
    required AppEventBus eventBus,
    required AppSettingsStore settingsStore,
  })  : _adapter = adapter,
        _workingMemory = workingMemory,
        _eventBus = eventBus,
        _settingsStore = settingsStore;

  VaultState get state => _state;
  AppSettings get settings => _settings;

  String? get lastVaultPath => _settings.lastVaultPath;
  int get vaultTimeoutSeconds => _settings.vaultTimeoutSeconds;

  Future<void> init() async {
    _settings = await _settingsStore.load();
    notifyListeners();

    final path = _settings.lastVaultPath;
    if (path == null) return;

    // Best-effort auto-mount; errors are reflected in state.
    await mount(path, persistAsLast: false);
  }

  Future<void> mount(String vaultPath, {bool persistAsLast = true}) async {
    final trimmed = vaultPath.trim();
    if (trimmed.isEmpty) return;

    _setState(VaultState.opening(trimmed));

    try {
      // Reset vault-scoped ephemeral data before opening a new vault.
      _workingMemory.resetVaultScope();

      await _adapter.openVault(vaultPath: trimmed);

      if (persistAsLast) {
        _settings = _settings.copyWith(lastVaultPath: trimmed);
        await _settingsStore.save(_settings);
      }

      _setState(VaultState.open(trimmed));
      _eventBus.publish(VaultOpened(trimmed));
    } catch (e) {
      final msg = e.toString();
      _setState(VaultState.error(trimmed, msg));
      _eventBus.publish(VaultOpenFailed(trimmed, msg));
    }
  }

  Future<void> close() async {
    final prev = _state.vaultPath;
    try {
      await _adapter.closeVault();
    } finally {
      _workingMemory.resetVaultScope();
      _setState(const VaultState.closed());
      _eventBus.publish(VaultClosed(prev));
    }
  }

  Future<void> clearLastVault() async {
    _settings = _settings.copyWith(clearLastVaultPath: true);
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    _settings = _settings.copyWith(vaultTimeoutSeconds: seconds);
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  void _setState(VaultState next) {
    _state = next;
    notifyListeners();
  }
}
