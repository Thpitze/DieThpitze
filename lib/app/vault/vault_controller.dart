/* lib/app/vault/vault_controller.dart */
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/vault/vault_errors.dart';
import '../../core/vault/vault_profile.dart';
import '../../core/vault/vault_profile_service.dart';
import '../core_adapter_impl.dart';
import '../events/app_event_bus.dart';
import '../events/vault_events.dart';
import '../events/working_memory.dart';
import '../settings/app_settings.dart';
import 'vault_state.dart';

class VaultController extends ChangeNotifier {
  final CoreAdapterImpl _adapter;
  final WorkingMemory _workingMemory;
  final AppEventBus _eventBus;
  final AppSettingsStore _settingsStore;

  final VaultProfileService _profileService = VaultProfileService();

  VaultState _state = const VaultState.closed();
  AppSettings _settings = AppSettings.defaults();

  VaultProfile? _profile;

  DateTime _lastUserActivityUtc = DateTime.now().toUtc();
  Timer? _inactivityTimer;

  // Session credential cache (cleared on lock/close/app exit)
  String? _sessionPassword;

  VaultController({
    required CoreAdapterImpl adapter,
    required WorkingMemory workingMemory,
    required AppEventBus eventBus,
    required AppSettingsStore settingsStore,
  }) : _adapter = adapter,
       _workingMemory = workingMemory,
       _eventBus = eventBus,
       _settingsStore = settingsStore;

  VaultState get state => _state;

  String? get lastVaultPath => _settings.lastVaultPath;
  List<String> get recentVaultPaths => _settings.recentVaultPaths;

  // Runtime source is vault profile when mounted; legacy host value only used as fallback.
  int get vaultTimeoutSeconds =>
      _profile?.security.timeoutSeconds ?? _settings.vaultTimeoutSeconds;

  Future<void> init() async {
    _settings = await _settingsStore.load();
    _restartInactivityTimer();
    notifyListeners();

    final path = _settings.lastVaultPath;
    if (path == null || path.trim().isEmpty) return;

    await mount(path, persistAsLast: false);
  }

  void recordUserActivity() {
    _lastUserActivityUtc = DateTime.now().toUtc();
    _restartInactivityTimer();
  }

  String _normalizePath(String input) {
    var s = input.trim();

    // Remove surrounding quotes sometimes coming from copy/paste
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      s = s.substring(1, s.length - 1);
    }

    return s;
  }

  Future<void> mount(String vaultPath, {bool persistAsLast = true}) async {
    final trimmed = _normalizePath(vaultPath);
    if (trimmed.isEmpty) return;

    recordUserActivity();
    _setState(VaultState.opening(trimmed));

    try {
      await _adapter.openVault(vaultPath: trimmed, password: _sessionPassword);

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

      await _loadOrCreateProfileForMountedVault(trimmed);

      _setState(VaultState.open(trimmed));
      _restartInactivityTimer();
      _eventBus.publish(VaultOpened(trimmed));
    } on AuthRequiredException catch (_) {
      // Best-effort: load profile even while locked (enables correct timeout + mode display in UI).
      try {
        await _loadOrCreateProfileForMountedVault(trimmed);
      } catch (_) {}

      _setState(VaultState.locked(trimmed, reason: 'auth_required'));
      _eventBus.publish(VaultLocked(trimmed, 'auth_required'));
    } on InvalidCredentialsException catch (e) {
      try {
        await _loadOrCreateProfileForMountedVault(trimmed);
      } catch (_) {}

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

  Future<void> closeVault() async {
    final prev = _state.vaultPath;
    _workingMemory.resetVaultScope();
    _wipeSessionCredentials();
    _profile = null;

    await _adapter.closeVault();
    _setState(const VaultState.closed());
    _eventBus.publish(VaultClosed(prev));
  }

  Future<void> lockNow({required String reason}) async {
    if (_state.kind != VaultStateKind.open) return;

    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    _workingMemory.resetVaultScope();
    _wipeSessionCredentials();

    await _adapter.closeVault();
    _setState(VaultState.locked(path, reason: reason));
    _eventBus.publish(VaultLocked(path, reason));
  }

  /// Unlocks a locked vault. If the vault has no auth.json, password may be empty.
  /// Session caching is always enabled (no "remember me" toggle anymore).
  Future<void> unlockWithPassword({required String password}) async {
    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    if (_state.kind != VaultStateKind.locked) return;

    recordUserActivity();
    _setState(VaultState.opening(path));

    try {
      await _adapter.openVault(
        vaultPath: path,
        password: password.trim().isEmpty ? null : password,
      );

      // Always remember for session (until lock/close/app exit)
      _sessionPassword = password.trim().isEmpty ? null : password;

      await _loadOrCreateProfileForMountedVault(path);

      _setState(VaultState.open(path));
      _restartInactivityTimer();
      _eventBus.publish(VaultUnlocked(path));
    } on AuthRequiredException catch (_) {
      try {
        await _loadOrCreateProfileForMountedVault(path);
      } catch (_) {}

      _setState(VaultState.locked(path, reason: 'auth_required'));
      _eventBus.publish(VaultLocked(path, 'auth_required'));
    } on InvalidCredentialsException catch (e) {
      try {
        await _loadOrCreateProfileForMountedVault(path);
      } catch (_) {}

      _setState(VaultState.locked(path, reason: 'invalid_credentials'));
      _eventBus.publish(VaultOpenFailed(path, e.message));
    } catch (e) {
      final msg = e.toString();
      _setState(VaultState.error(path, msg));
      _eventBus.publish(VaultOpenFailed(path, msg));
    }
  }

  Future<void> _loadOrCreateProfileForMountedVault(String vaultPath) async {
    final root = Directory(vaultPath);

    // Migration hook (P17 Step 6):
    // If profile.json does not exist yet, create defaults, then seed timeout from legacy host setting once.
    final profileFile = File(
      _joinPath(root.path, VaultProfileService.profileFileName),
    );
    final existed = await profileFile.exists();

    final loaded = await _profileService.loadOrCreate(root);

    if (!existed) {
      final legacyTimeout = _settings.vaultTimeoutSeconds;

      final seeded = loaded.security.timeoutSeconds == legacyTimeout
          ? loaded
          : loaded.copyWith(
              security: loaded.security.copyWith(timeoutSeconds: legacyTimeout),
            );

      if (seeded != loaded) {
        await _profileService.save(root, seeded);
      }

      _profile = seeded;
    } else {
      _profile = loaded;
    }
  }

  String _joinPath(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }

  void _wipeSessionCredentials() {
    _sessionPassword = null;
  }

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    final timeout = _profile?.security.timeoutSeconds ?? 0;
    if (timeout <= 0) return;

    _inactivityTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_state.kind != VaultStateKind.open) return;

      final now = DateTime.now().toUtc();
      final idle = now.difference(_lastUserActivityUtc).inSeconds;
      if (idle < timeout) return;

      await lockNow(reason: 'timeout');
    });
  }

  void _setState(VaultState s) {
    _state = s;
    notifyListeners();
  }

  Future<void> removeRecent(String path) async {
    final trimmed = _normalizePath(path);
    if (trimmed.isEmpty) return;

    _settings = _settings.copyWith(
      recentVaultPaths: _settings.recentVaultPaths
          .where((p) => p != trimmed)
          .toList(growable: false),
    );
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    // Persist to vault profile when mounted; otherwise fall back to legacy host setting.
    if (_state.kind == VaultStateKind.open ||
        _state.kind == VaultStateKind.locked) {
      final root = Directory(path);
      final cur = await _profileService.loadOrCreate(root);
      final next = cur.copyWith(
        security: cur.security.copyWith(timeoutSeconds: seconds),
      );
      await _profileService.save(root, next);
      _profile = next;
    } else {
      _settings = _settings.copyWith(vaultTimeoutSeconds: seconds);
      await _settingsStore.save(_settings);
    }

    _restartInactivityTimer();
    notifyListeners();
  }
}
