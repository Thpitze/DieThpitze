// lib/core/vault/vault_identity_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:thpitze_main/core/vault/vault_errors.dart';
import 'package:thpitze_main/core/vault/vault_info.dart';

class VaultIdentityService {
  static const String vaultFileName = 'vault.json';
  static const Uuid _uuid = Uuid();

  /// Creates (if needed) the vault root directory and writes a new vault.json.
  /// Fails if vault.json already exists.
  VaultInfo initVault(Directory vaultRoot) {
    // Auto-create directory (including parents) if missing.
    if (!vaultRoot.existsSync()) {
      vaultRoot.createSync(recursive: true);
    }

    final file = File(_vaultJsonPath(vaultRoot));
    if (file.existsSync()) {
      throw VaultInvalidException('vault.json already exists: ${file.path}');
    }

    final info = VaultInfo(
      schemaVersionValue: VaultInfo.schemaVersion,
      vaultId: _uuid.v4(),
      createdAtUtc: DateTime.now().toUtc().toIso8601String(),
    );

    file.writeAsStringSync(info.toJsonString(pretty: true));
    return info;
  }

  /// Reads vault.json and parses it.
  VaultInfo readVaultInfo(Directory vaultRoot) {
    final file = File(_vaultJsonPath(vaultRoot));
    if (!file.existsSync()) {
      throw VaultNotFoundException('vault.json not found at: ${file.path}');
    }

    try {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        throw VaultCorruptException('vault.json is not a JSON object.');
      }

      try {
        return VaultInfo.fromJson(decoded);
      } on Exception catch (e) {
        throw VaultCorruptException('vault.json failed schema parsing: $e');
      }
    } on FormatException catch (e) {
      // JSON parse error
      throw VaultCorruptException('vault.json is not valid JSON: ${e.message}');
    } on FileSystemException catch (e) {
      throw VaultCorruptException('vault.json IO error: ${e.message}');
    }
  }

  /// Validates vault.json.
  VaultInfo validateVault(Directory vaultRoot) {
    final info = readVaultInfo(vaultRoot);

    if (info.schemaVersionValue != VaultInfo.schemaVersion) {
      throw VersionUnsupportedException(
        'schemaVersion mismatch: file=${info.schemaVersionValue} expected=${VaultInfo.schemaVersion}',
        foundSchemaVersion: info.schemaVersionValue,
        expectedSchemaVersion: VaultInfo.schemaVersion,
      );
    }

    if (!_looksLikeUuid(info.vaultId)) {
      throw VaultInvalidException(
        'vaultId is not a valid UUID: ${info.vaultId}',
      );
    }

    if (!_looksLikeIsoUtc(info.createdAtUtc)) {
      throw VaultInvalidException(
        'createdAtUtc is not valid ISO-8601 UTC (must end with Z): ${info.createdAtUtc}',
      );
    }

    return info;
  }

  String _vaultJsonPath(Directory vaultRoot) {
    return '${vaultRoot.path}${Platform.pathSeparator}$vaultFileName';
  }

  bool _looksLikeUuid(String s) {
    final re = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return re.hasMatch(s);
  }

  bool _looksLikeIsoUtc(String s) {
    // Require UTC "Z" to avoid local-time ambiguity.
    if (!s.endsWith('Z')) return false;
    final dt = DateTime.tryParse(s);
    return dt != null && dt.isUtc;
  }
}
