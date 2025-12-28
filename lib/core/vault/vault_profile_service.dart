/* lib/core/vault/vault_profile_service.dart */
import 'dart:convert';
import 'dart:io';

import 'package:thpitze_main/core/vault/vault_errors.dart';
import 'package:thpitze_main/core/vault/vault_profile.dart';

class VaultProfileService {
  static const String profileFileName = 'profile.json';

  /// Loads <vaultRoot>/profile.json.
  /// If missing, creates defaults and persists them.
  ///
  /// Structural invalidity => VaultCorruptException.
  /// Unsupported schema => VersionUnsupportedException.
  Future<VaultProfile> loadOrCreate(Directory vaultRoot) async {
    final file = File(_join(vaultRoot.path, profileFileName));

    if (!await file.exists()) {
      final p = VaultProfile.defaults();
      await save(vaultRoot, p);
      return p;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw VaultCorruptException('profile.json is not a JSON object');
      }
      return VaultProfile.fromJsonMap(Map<String, dynamic>.from(decoded));
    } on VaultException {
      rethrow;
    } on FormatException catch (e) {
      throw VaultCorruptException('profile.json invalid JSON: ${e.message}');
    } on IOException catch (e) {
      throw VaultCorruptException('profile.json IO failure: $e');
    } catch (e) {
      throw VaultCorruptException('profile.json read failure: $e');
    }
  }

  /// Atomic write:
  /// - write temp in same directory
  /// - rename over target
  Future<void> save(Directory vaultRoot, VaultProfile profile) async {
    final file = File(_join(vaultRoot.path, profileFileName));
    final tmp = File(_join(
      vaultRoot.path,
      '$profileFileName.tmp.${DateTime.now().microsecondsSinceEpoch}',
    ));

    try {
      final json = profile.toJsonString(pretty: true);
      await tmp.writeAsString(json, flush: true);

      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } on IOException catch (e) {
      // best-effort cleanup
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      throw VaultCorruptException('profile.json write failure: $e');
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      throw VaultCorruptException('profile.json write failure: $e');
    }
  }

  String _join(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }
}
