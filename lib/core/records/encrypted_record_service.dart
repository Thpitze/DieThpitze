// lib/core/records/encrypted_record_service.dart
//
// Stores record files encrypted-at-rest when vault encryption is enabled.
//
// File format on disk (for encrypted vaults):
// - The entire record markdown document (frontmatter + body) is encoded as UTF-8 bytes,
//   encrypted via VaultEncryptionService (AES-GCM), then encoded to Base64 using
//   VaultPayloadCodec (MAGIC|VERSION|NONCE|CT|TAG). The file content is the UTF-8 bytes
//   of that Base64 string.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../security/vault_crypto_context.dart';
import '../security/vault_crypto_models.dart';
import '../security/vault_payload_codec.dart';
import 'record.dart';
import 'record_codec.dart';
import 'record_header.dart';
import '../time/clock.dart';
import '../vault/vault_errors.dart';

class EncryptedRecordService {
  static const String recordsDirName = 'records';
  static const String trashDirName = 'trash';

  final RecordCodec codec;
  final Clock clock;

  EncryptedRecordService({required this.codec, required this.clock});

  Future<List<RecordHeader>> listHeaders({
    required Directory vaultRoot,
    required VaultCryptoContext crypto,
  }) async {
    _requireUnlocked(crypto);

    final ids = await listIds(vaultRoot: vaultRoot);
    final headers = <RecordHeader>[];

    for (final id in ids) {
      final r = await read(vaultRoot: vaultRoot, crypto: crypto, id: id);
      headers.add(
        RecordHeader(
          id: r.id,
          updatedAtUtc: r.updatedAtUtc,
          type: r.type,
          tags: r.tags,
          title: _extractTitle(r.bodyMarkdown),
        ),
      );
    }

    headers.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    return headers;
  }

  Future<List<String>> listIds({required Directory vaultRoot}) async {
    final dir = _recordsDir(vaultRoot);
    if (!dir.existsSync()) return <String>[];

    final ids = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.md') continue;

      final base = p.basenameWithoutExtension(entity.path);
      if (base.trim().isEmpty) continue;

      ids.add(base);
    }

    ids.sort();
    return ids;
  }

  Future<Record> read({
    required Directory vaultRoot,
    required VaultCryptoContext crypto,
    required String id,
  }) async {
    _requireUnlocked(crypto);

    final file = File(_recordPath(recordsDir: _recordsDir(vaultRoot), id: id));
    if (!file.existsSync()) {
      throw VaultNotFoundException('Record not found: ${file.path}');
    }

    final b64 = await file.readAsString();
    final payload = VaultPayloadCodec.decodeB64(b64);

    final plainBytes = await crypto.requireEncryptionService.decrypt(
      info: crypto.requireInfo,
      key: crypto.requireKey,
      payload: payload,
    );

    final content = utf8.decode(plainBytes);
    final record = codec.decode(content);

    if (record.id != id) {
      throw VaultInvalidException(
        'Record id mismatch: filename=$id frontmatter=${record.id}',
      );
    }

    return record;
  }

  Future<Record> create({
    required Directory vaultRoot,
    required VaultCryptoContext crypto,
    required Record record,
  }) async {
    _requireUnlocked(crypto);

    final recordsDir = _ensureRecordsDir(vaultRoot);
    final file = File(_recordPath(recordsDir: recordsDir, id: record.id));

    final plain = Uint8List.fromList(utf8.encode(codec.encode(record)));

    final payload = await crypto.requireEncryptionService.encrypt(
      info: crypto.requireInfo,
      key: crypto.requireKey,
      plaintext: plain,
    );

    final b64 = VaultPayloadCodec.encodeB64(payload);

    await _writeStringAtomic(file, b64);
    return record;
  }

  Future<Record> update({
    required Directory vaultRoot,
    required VaultCryptoContext crypto,
    required String id,
    required Record updated,
  }) async {
    _requireUnlocked(crypto);

    final file = File(_recordPath(recordsDir: _recordsDir(vaultRoot), id: id));
    if (!file.existsSync()) {
      throw VaultNotFoundException('Record not found: ${file.path}');
    }

    final plain = Uint8List.fromList(utf8.encode(codec.encode(updated)));

    final payload = await crypto.requireEncryptionService.encrypt(
      info: crypto.requireInfo,
      key: crypto.requireKey,
      plaintext: plain,
    );

    final b64 = VaultPayloadCodec.encodeB64(payload);

    await _writeStringAtomic(file, b64);
    return updated;
  }

  void deleteRecord({
    required Directory vaultRoot,
    required String recordId,
  }) {
    final src = File(_recordPath(recordsDir: _recordsDir(vaultRoot), id: recordId));
    if (!src.existsSync()) {
      throw VaultNotFoundException('Record not found: ${src.path}');
    }

    final trashDir = _ensureTrashDir(vaultRoot);
    final dst = File(_recordPath(recordsDir: trashDir, id: recordId));
    if (dst.existsSync()) {
      throw VaultInvalidException('Trash already contains record: ${dst.path}');
    }

    src.renameSync(dst.path);
  }

  void restoreRecord({
    required Directory vaultRoot,
    required String recordId,
  }) {
    final src = File(_recordPath(recordsDir: _trashDir(vaultRoot), id: recordId));
    if (!src.existsSync()) {
      throw VaultNotFoundException('Trashed record not found: ${src.path}');
    }

    final recordsDir = _ensureRecordsDir(vaultRoot);
    final dst = File(_recordPath(recordsDir: recordsDir, id: recordId));
    if (dst.existsSync()) {
      throw VaultInvalidException('Active records already contain id: ${dst.path}');
    }

    src.renameSync(dst.path);
  }

  // ---------- dirs / paths ----------

  Directory _recordsDir(Directory vaultRoot) =>
      Directory(p.join(vaultRoot.path, recordsDirName));

  Directory _trashDir(Directory vaultRoot) =>
      Directory(p.join(vaultRoot.path, trashDirName));

  Directory _ensureRecordsDir(Directory vaultRoot) {
    if (!vaultRoot.existsSync()) {
      throw VaultNotFoundException('Vault root does not exist: ${vaultRoot.path}');
    }
    final dir = _recordsDir(vaultRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Directory _ensureTrashDir(Directory vaultRoot) {
    if (!vaultRoot.existsSync()) {
      throw VaultNotFoundException('Vault root does not exist: ${vaultRoot.path}');
    }
    final dir = _trashDir(vaultRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  String _recordPath({required Directory recordsDir, required String id}) {
    return p.join(recordsDir.path, '$id.md');
  }

  void _requireUnlocked(VaultCryptoContext crypto) {
    if (!crypto.isEncrypted) {
      throw StateError('EncryptedRecordService used for unencrypted vault.');
    }
    if (crypto.isLocked) {
      // Wrong password / not unlocked yet.
      throw const VaultCryptoLocked();
    }
  }

  String _extractTitle(String bodyMarkdown) {
    final lines = bodyMarkdown.replaceAll('\r\n', '\n').split('\n');

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        final cleaned = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (cleaned.isNotEmpty) return cleaned;
      }

      return line;
    }

    return '(untitled)';
  }

  // Atomic write: temp → flush → rename.
  Future<void> _writeStringAtomic(File target, String text) async {
    target.parent.createSync(recursive: true);

    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsString(text, flush: true);
    tmp.renameSync(target.path);
  }
}
