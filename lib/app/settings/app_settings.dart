/* lib/app/settings/app_settings.dart */
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AppSettings {
  final String? lastVaultPath;
  final List<String> recentVaultPaths; // MRU, max N enforced on write
  final int vaultTimeoutSeconds; // 0 disables

  const AppSettings({
    required this.lastVaultPath,
    required this.recentVaultPaths,
    required this.vaultTimeoutSeconds,
  });

  factory AppSettings.defaults() => const AppSettings(
        lastVaultPath: null,
        recentVaultPaths: <String>[],
        vaultTimeoutSeconds: 0,
      );

  AppSettings copyWith({
    String? lastVaultPath,
    bool clearLastVaultPath = false,
    List<String>? recentVaultPaths,
    int? vaultTimeoutSeconds,
  }) {
    return AppSettings(
      lastVaultPath: clearLastVaultPath ? null : (lastVaultPath ?? this.lastVaultPath),
      recentVaultPaths: recentVaultPaths ?? this.recentVaultPaths,
      vaultTimeoutSeconds: vaultTimeoutSeconds ?? this.vaultTimeoutSeconds,
    );
  }

  // --- Helpers (host-only) ---

  static String normalizeVaultPath(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    // Normalize separators and remove redundant segments.
    final norm = p.normalize(t);
    return norm.trim();
  }

  static List<String> insertRecentPath({
    required List<String> current,
    required String newPath,
    int maxItems = 10,
  }) {
    final n = normalizeVaultPath(newPath);
    if (n.isEmpty) return current;

    final next = <String>[n];
    for (final s in current) {
      final sn = normalizeVaultPath(s);
      if (sn.isEmpty) continue;
      if (sn.toLowerCase() == n.toLowerCase()) continue; // de-dupe case-insensitive
      next.add(sn);
      if (next.length >= maxItems) break;
    }
    return next;
  }

  static List<String> removeRecentPath({
    required List<String> current,
    required String removePath,
  }) {
    final r = normalizeVaultPath(removePath);
    if (r.isEmpty) return current;

    return current
        .map(normalizeVaultPath)
        .where((s) => s.isNotEmpty)
        .where((s) => s.toLowerCase() != r.toLowerCase())
        .toList(growable: false);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'lastVaultPath': lastVaultPath,
        'recentVaultPaths': recentVaultPaths,
        'vaultTimeoutSeconds': vaultTimeoutSeconds,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final lastVaultPath = json['lastVaultPath'];
    final vts = json['vaultTimeoutSeconds'];
    final rec = json['recentVaultPaths'];

    List<String> recent = const <String>[];
    if (rec is List) {
      final tmp = <String>[];
      for (final it in rec) {
        if (it is String) {
          final n = normalizeVaultPath(it);
          if (n.isNotEmpty) tmp.add(n);
        }
      }
      recent = tmp;
    }

    return AppSettings(
      lastVaultPath: lastVaultPath is String && lastVaultPath.trim().isNotEmpty ? normalizeVaultPath(lastVaultPath) : null,
      recentVaultPaths: recent,
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
