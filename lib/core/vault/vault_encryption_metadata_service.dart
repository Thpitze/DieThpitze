 // lib/core/vault/vault_encryption_metadata_service.dart
 //
 // P19.1: Read/write versioned encryption metadata from vault root.
 // P23: Metadata redundancy: encryption.json + encryption.json.bak (Option A).
 //
 // Rules:
 // - Missing encryption.json => unencrypted vault (VaultEncryptionInfo.none)
 // - Invalid schema/state/version => VaultInvalidException (Error semantics)
 //
 // Atomic write semantics: temp file then rename.
 // NOTE: Dart cannot reliably fsync directories cross-platform without native code.
 //       We still do flush=true and atomic rename; directory fsync is a future hardening item.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:thpitze_main/core/vault/vault_encryption_info.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

class VaultEncryptionMetadataService {
  static const String fileName = 'encryption.json';
  static const String backupFileName = 'encryption.json.bak';

  VaultEncryptionInfo loadOrDefault({required Directory vaultRoot}) {
    final primary = _file(vaultRoot, fileName);
    final backup = _file(vaultRoot, backupFileName);

    if (!primary.existsSync()) {
      // If primary missing, we still consider the vault unencrypted.
      // (Backup alone is not treated as authoritative without the primary.)
      return const VaultEncryptionInfo.none();
    }

    // Try primary first
    try {
      return _readAndValidate(primary);
    } catch (e) {
      // If primary corrupt/invalid, try backup
      if (!backup.existsSync()) {
        // No redundancy available => fail loudly (P23: metadata corruption blocks unlock)
        if (e is VaultException) rethrow;
        throw VaultInvalidException('Invalid encryption metadata: $e');
      }

      try {
        final info = _readAndValidate(backup);

        // Best-effort restore primary from backup
        try {
          _writeAtomicSync(primary, _prettyJson(info));
        } catch (_) {
          // ignore restore failure; we can still continue using backup-derived info
        }

        return info;
      } catch (e2) {
        // Both copies failed
        if (e2 is VaultException) rethrow;
        throw VaultInvalidException('Invalid encryption metadata (primary+backup): $e2');
      }
    }
  }

  Future<void> save({
    required Directory vaultRoot,
    required VaultEncryptionInfo info,
  }) async {
    _validate(info);

    if (!vaultRoot.existsSync()) {
      throw VaultNotFoundException(
        'Vault root does not exist: ${vaultRoot.path}',
      );
    }

    final primary = _file(vaultRoot, fileName);
    final backup = _file(vaultRoot, backupFileName);

    final jsonText = _prettyJson(info);

    // Write primary atomically
    await _writeAtomic(primary, jsonText);

    // Write backup atomically (redundancy)
    await _writeAtomic(backup, jsonText);
  }

  // ---------- helpers ----------

  File _file(Directory vaultRoot, String name) => File(p.join(vaultRoot.path, name));

  VaultEncryptionInfo _readAndValidate(File file) {
    try {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('encryption metadata must be a JSON object');
      }

      final info = VaultEncryptionInfo.fromJson(decoded);
      _validate(info);
      return info;
    } on VaultException {
      rethrow;
    } catch (e) {
      throw VaultInvalidException('Invalid encryption metadata: $e');
    }
  }

  String _prettyJson(VaultEncryptionInfo info) =>
      '${const JsonEncoder.withIndent('  ').convert(info.toJson())}\n';

  Future<void> _writeAtomic(File target, String text) async {
    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsString(text, flush: true);

    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // best-effort cleanup
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  // Best-effort sync write (used for restore path inside loadOrDefault)
  void _writeAtomicSync(File target, String text) {
    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    tmp.writeAsStringSync(text, flush: true);
    tmp.renameSync(target.path);
  }

  void _validate(VaultEncryptionInfo info) {
    if (info.schema.trim() != VaultEncryptionInfo.schemaV1) {
      throw VaultInvalidException(
        'Unsupported encryption schema: ${info.schema}',
      );
    }

    final state = info.state.trim();
    if (state != 'none' && state != 'enabled') {
      throw VaultInvalidException(
        'Unsupported encryption state: ${info.state}',
      );
    }

    if (state == 'none') {
      // When unencrypted, version must not be set.
      if (info.version != null) {
        throw VaultInvalidException(
          'Unencrypted vault must not declare version',
        );
      }
      return;
    }

    // enabled:
    if (info.version == null) {
      throw VaultInvalidException('Encrypted vault must declare version');
    }
    if (info.version != 1) {
      throw VaultInvalidException(
        'Unsupported encryption version: ${info.version}',
      );
    }

    // Sanity check informational fields (do not enforce exact strings yet).
    if ((info.cipher ?? '').toString().trim().isEmpty) {
      throw VaultInvalidException('Encrypted vault must declare cipher');
    }
    if ((info.kdf ?? '').toString().trim().isEmpty) {
      throw VaultInvalidException('Encrypted vault must declare kdf');
    }
  }
}
