/* lib/app/vault/vault_controller.dart */
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/vault/vault_errors.dart';
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

  DateTime _lastUserActivityUtc = DateTime.now().toUtc();
  Timer? _inactivityTimer;

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
  List<String> get recentVaultPaths => _settings.recentVaultPaths;
  int get vaultTimeoutSeconds => _settings.vaultTimeoutSeconds;

  Future<void> init() async {
    _settings = await _settingsStore.load();
    _restartInactivityTimer();
    notifyListeners();

    final path = _settings.lastVaultPath;
    if (path == null) return;

    await mount(path, persistAsLast: false);
  }

  void recordUserActivity() {
    _lastUserActivityUtc = DateTime.now().toUtc();
  }

  Future<void> mount(String vaultPath, {bool persistAsLast = true}) async {
    final trimmed = AppSettings.normalizeVaultPath(vaultPath);
    if (trimmed.isEmpty) return;

    recordUserActivity();
    _setState(VaultState.opening(trimmed));

    try {
      if (!await Directory(trimmed).exists()) {
        throw FileSystemException('Folder does not exist', trimmed);
      }

      // Reset vault-scoped ephemeral data before opening a new vault.
      _workingMemory.resetVaultScope();

      await _adapter.openVault(vaultPath: trimmed);

      if (persistAsLast) {
        _settings = _settings.copyWith(
          lastVaultPath: trimmed,
          recentVaultPaths: AppSettings.insertRecentPath(
            current: _settings.recentVaultPaths,
            newPath: trimmed,
            maxItems: 10,
          ),
        );
        await _settingsStore.save(_settings);
      }

      _setState(VaultState.open(trimmed));
      _eventBus.publish(VaultOpened(trimmed));
    } on AuthRequiredException catch (_) {
      // P15: Auth required => Locked (recoverable)
      _setState(VaultState.locked(trimmed, reason: 'auth_required'));
      _eventBus.publish(VaultLocked(trimmed, 'auth_required'));
    } on InvalidCredentialsException catch (e) {
      // P15: Invalid credentials => remain Locked, explicit failure event
      _setState(VaultState.locked(trimmed, reason: 'invalid_credentials'));
      _eventBus.publish(VaultOpenFailed(trimmed, e.message));
    } on VaultCorruptException catch (e) {
      final msg = e.message;
      _setState(VaultState.error(trimmed, msg));
      _eventBus.publish(VaultOpenFailed(trimmed, msg));
    } on VersionUnsupportedException catch (e) {
      final msg = e.message;
      _setState(VaultState.error(trimmed, msg));
      _eventBus.publish(VaultOpenFailed(trimmed, msg));
    } catch (e) {
      final msg = e.toString();
      _setState(VaultState.error(trimmed, msg));
      _eventBus.publish(VaultOpenFailed(trimmed, msg));
    }
  }

  Future<void> close() async {
    recordUserActivity();
    final prev = _state.vaultPath;
    try {
      await _adapter.closeVault();
    } finally {
      _workingMemory.resetVaultScope();
      _setState(const VaultState.closed());
      _eventBus.publish(VaultClosed(prev));
    }
  }

  Future<void> lockNow({String reason = 'manual'}) async {
    if (!_state.isOpen) return;
    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    recordUserActivity();
    _workingMemory.resetVaultScope();
    _setState(VaultState.locked(path, reason: reason));
    _eventBus.publish(VaultLocked(path, reason));
  }

  Future<void> unlockStub() async {
    // Placeholder until credential prompt + session cache exists.
    if (!_state.isLocked) return;
    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    recordUserActivity();
    _setState(VaultState.open(path));
    _eventBus.publish(VaultUnlocked(path));
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    final s = seconds < 0 ? 0 : seconds;
    _settings = _settings.copyWith(vaultTimeoutSeconds: s);
    await _settingsStore.save(_settings);
    _restartInactivityTimer();
    notifyListeners();
  }

  Future<void> removeRecent(String vaultPath) async {
    _settings = _settings.copyWith(
      recentVaultPaths: AppSettings.removeRecentPath(
        current: _settings.recentVaultPaths,
        removePath: vaultPath,
      ),
    );
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    final timeout = _settings.vaultTimeoutSeconds;
    if (timeout <= 0) return;

    _inactivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_state.isOpen) return;

      final now = DateTime.now().toUtc();
      final elapsed = now.difference(_lastUserActivityUtc).inSeconds;

      if (elapsed >= timeout) {
        lockNow(reason: 'timeout');
      }
    });
  }

  void _setState(VaultState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }
}
