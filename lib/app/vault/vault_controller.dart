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

  // Session-only credential cache (cleared on lock/close/app exit)
  String? _sessionPassword;

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
  VaultProfile? get profile => _profile;

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
    if (path == null) return;

    await mount(path, persistAsLast: false);
  }

  void recordUserActivity() {
    _lastUserActivityUtc = DateTime.now().toUtc();
  }

  String _normalizePath(String p) {
    var s = p.trim();
    if (s.isEmpty) return '';

    // Windows: normalize to backslashes for MRU de-dup stability
    s = s.replaceAll('/', r'\');

    // Remove trailing slashes/backslashes (but not "C:\")
    while (s.length > 3 && (s.endsWith(r'\') || s.endsWith('/'))) {
      s = s.substring(0, s.length - 1);
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
      // P16: Auth required => Locked (recoverable)
      _setState(VaultState.locked(trimmed, reason: 'auth_required'));
      _eventBus.publish(VaultLocked(trimmed, 'auth_required'));
    } on InvalidCredentialsException catch (e) {
      // P16: Invalid credentials => Locked + explicit failure event
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
    _restartInactivityTimer();
    _eventBus.publish(VaultClosed(prev));
  }

  Future<void> lockNow({String reason = 'manual'}) async {
    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    if (_state.kind != VaultStateKind.open) return;

    _workingMemory.resetVaultScope();
    _wipeSessionCredentials();

    _setState(VaultState.locked(path, reason: reason));
    _eventBus.publish(VaultLocked(path, reason));
  }

  Future<void> unlockWithPassword({
    required String password,
    required bool rememberForSession,
  }) async {
    final path = _state.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    if (_state.kind != VaultStateKind.locked) return;

    recordUserActivity();
    _setState(VaultState.opening(path));

    try {
      await _adapter.openVault(vaultPath: path, password: password);

      _sessionPassword = rememberForSession ? password : null;

      await _loadOrCreateProfileForMountedVault(path);

      _setState(VaultState.open(path));
      _restartInactivityTimer();
      _eventBus.publish(VaultUnlocked(path));
    } on AuthRequiredException catch (_) {
      _setState(VaultState.locked(path, reason: 'auth_required'));
      _eventBus.publish(VaultLocked(path, 'auth_required'));
    } on InvalidCredentialsException catch (e) {
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
    final profileFile = File(_joinPath(root.path, VaultProfileService.profileFileName));
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
      final elapsed = now.difference(_lastUserActivityUtc).inSeconds;
      if (elapsed > timeout) {
        await lockNow(reason: 'timeout');
      }
    });
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    final s = seconds < 0 ? 0 : seconds;

    final path = _state.vaultPath;
    if (path != null && path.trim().isNotEmpty) {
      // Vault-scoped timeout (P17): persist into profile.json.
      final current = _profile ?? VaultProfile.defaults();
      final next = current.copyWith(
        security: current.security.copyWith(timeoutSeconds: s),
      );

      _profile = next;
      await _profileService.save(Directory(path), next);

      _restartInactivityTimer();
      notifyListeners();
      return;
    }

    // No vault mounted: keep legacy host setting for backwards compatibility.
    _settings = _settings.copyWith(vaultTimeoutSeconds: s);
    await _settingsStore.save(_settings);

    _restartInactivityTimer();
    notifyListeners();
  }

  void _setState(VaultState next) {
    _state = next;
    notifyListeners();
  }
  Future<void> removeRecent(String vaultPath) async {
    final trimmed = _normalizePath(vaultPath);
    if (trimmed.isEmpty) return;

    final current = _settings.recentVaultPaths;
    final next = <String>[
      for (final p in current)
        if (_normalizePath(p) != trimmed) p,
    ];

    if (listEquals(current, next)) return;

    _settings = _settings.copyWith(recentVaultPaths: next);
    await _settingsStore.save(_settings);
    notifyListeners();
  }


  @override
  void dispose() {
    _wipeSessionCredentials();
    _inactivityTimer?.cancel();
    super.dispose();
  }
}

