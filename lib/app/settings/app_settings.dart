/* lib/app/settings/app_settings.dart */
import 'dart:convert';
import 'dart:io';

class AppSettings {
  final String? lastVaultPath;
  final int vaultTimeoutSeconds;

  const AppSettings({
    required this.lastVaultPath,
    required this.vaultTimeoutSeconds,
  });

  factory AppSettings.defaults() => const AppSettings(
        lastVaultPath: null,
        vaultTimeoutSeconds: 0,
      );

  AppSettings copyWith({
    String? lastVaultPath,
    bool clearLastVaultPath = false,
    int? vaultTimeoutSeconds,
  }) {
    return AppSettings(
      lastVaultPath: clearLastVaultPath ? null : (lastVaultPath ?? this.lastVaultPath),
      vaultTimeoutSeconds: vaultTimeoutSeconds ?? this.vaultTimeoutSeconds,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'lastVaultPath': lastVaultPath,
        'vaultTimeoutSeconds': vaultTimeoutSeconds,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final lastVaultPath = json['lastVaultPath'];
    final vts = json['vaultTimeoutSeconds'];

    return AppSettings(
      lastVaultPath: lastVaultPath is String && lastVaultPath.trim().isNotEmpty ? lastVaultPath : null,
      vaultTimeoutSeconds: vts is int ? vts : 0,
    );
  }
}

class AppSettingsStore {
  final File _file;

  AppSettingsStore._(this._file);

  /// Default location:
  /// - Windows: %APPDATA%\Thpitze\settings.json
  /// - Else:    $HOME/.thpitze/settings.json
  factory AppSettingsStore.defaultStore() {
    Directory baseDir;

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        baseDir = Directory(appData);
      } else {
        // Fallbacks (rare, but don't crash)
        final local = Platform.environment['LOCALAPPDATA'];
        baseDir = Directory(
          (local != null && local.trim().isNotEmpty) ? local : Directory.current.path,
        );
      }
      baseDir = Directory('${baseDir.path}\\Thpitze');
    } else {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      baseDir = Directory('$home/.thpitze');
    }

    final file = File('${baseDir.path}${Platform.pathSeparator}settings.json');
    return AppSettingsStore._(file);
  }

  Future<AppSettings> load() async {
    try {
      if (!await _file.exists()) return AppSettings.defaults();

      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw);

      if (decoded is! Map) return AppSettings.defaults();

      final map = <String, Object?>{};
      decoded.forEach((k, v) {
        if (k is String) map[k] = v;
      });

      return AppSettings.fromJson(map);
    } catch (_) {
      // Corrupt settings should never brick the app.
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    final dir = _file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final raw = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    await _file.writeAsString(raw);
  }
}
