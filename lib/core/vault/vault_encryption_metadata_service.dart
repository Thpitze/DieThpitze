// lib/core/vault/vault_encryption_metadata_service.dart
//
// P19.1: Read/write versioned encryption metadata from vault root.
// This does NOT implement cryptography yet; it only declares encryption state.
//
// Rules:
// - Missing encryption.json => unencrypted vault (VaultEncryptionInfo.none)
// - Invalid schema/state/version => VaultInvalidException (Error semantics)
//
// Atomic write semantics: temp file then rename.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:thpitze_main/core/vault/vault_encryption_info.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

class VaultEncryptionMetadataService {
  static const String fileName = 'encryption.json';

  VaultEncryptionInfo loadOrDefault({required Directory vaultRoot}) {
    final file = _file(vaultRoot);

    if (!file.existsSync()) {
      return const VaultEncryptionInfo.none();
    }

    try {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('encryption.json must be a JSON object');
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

    final file = _file(vaultRoot);
    final jsonText =
        '${const JsonEncoder.withIndent('  ').convert(info.toJson())}\n';

    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    await tmp.writeAsString(jsonText, flush: true);

    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      // If rename fails for some reason, try best-effort cleanup.
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {
        // ignore cleanup failure
      }
      rethrow;
    }
  }

  // ---------- helpers ----------

  File _file(Directory vaultRoot) => File(p.join(vaultRoot.path, fileName));

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
