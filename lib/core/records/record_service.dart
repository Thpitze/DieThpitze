// lib/core/records/record_service.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:thpitze_main/core/records/record.dart';
import 'package:thpitze_main/core/records/record_codec.dart';
import 'package:thpitze_main/core/records/record_header.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

class RecordService {
  static const String recordsDirName = 'records';
  static const String trashDirName = 'trash';
  static const Uuid _uuid = Uuid();

  final RecordCodec codec;
  final Clock clock;

  RecordService({required this.codec, required this.clock});

  /// Returns record ids (filenames without .md), sorted alphabetically.
  List<String> listIds({required Directory vaultRoot}) {
    final dir = _recordsDir(vaultRoot);
    if (!dir.existsSync()) return <String>[];

    final ids = <String>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.md') continue;

      final base = p.basenameWithoutExtension(entity.path);
      if (base.trim().isEmpty) continue;

      ids.add(base);
    }

    ids.sort();
    return ids;
  }

  /// Returns lightweight headers for display (sorted by updatedAtUtc desc).
  List<RecordHeader> listHeaders({required Directory vaultRoot}) {
    final ids = listIds(vaultRoot: vaultRoot);

    final headers = <RecordHeader>[];
    for (final id in ids) {
      final record = read(vaultRoot: vaultRoot, id: id);

      headers.add(
        RecordHeader(
          id: record.id,
          updatedAtUtc: record.updatedAtUtc,
          type: record.type,
          tags: record.tags,
          title: _extractTitle(record.bodyMarkdown),
        ),
      );
    }

    headers.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    return headers;
  }

  /// Returns trashed headers for display (sorted by updatedAtUtc desc).
  List<RecordHeader> listTrashedHeaders({required Directory vaultRoot}) {
    final dir = _trashDir(vaultRoot);
    if (!dir.existsSync()) return <RecordHeader>[];

    final headers = <RecordHeader>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.md') continue;

      final id = p.basenameWithoutExtension(entity.path).trim();
      if (id.isEmpty) continue;

      final record = _readFromFile(file: entity, expectedId: id);

      headers.add(
        RecordHeader(
          id: record.id,
          updatedAtUtc: record.updatedAtUtc,
          type: record.type,
          tags: record.tags,
          title: _extractTitle(record.bodyMarkdown),
        ),
      );
    }

    headers.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    return headers;
  }

  Record create({
    required Directory vaultRoot,
    String type = 'note',
    List<String> tags = const [],
    String bodyMarkdown = '',
  }) {
    final recordsDir = _ensureRecordsDir(vaultRoot);

    final now = clock.nowUtc().toIso8601String();
    final id = _uuid.v4();

    final record = Record(
      id: id,
      createdAtUtc: now,
      updatedAtUtc: now,
      type: type,
      tags: List<String>.from(tags),
      bodyMarkdown: bodyMarkdown,
    );

    final file = File(_recordPath(recordsDir: recordsDir, id: id));

    // P23: atomic write (temp -> flush -> rename)
    _writeStringAtomicSync(file, codec.encode(record));

    return record;
  }

  Record read({required Directory vaultRoot, required String id}) {
    final file = File(_recordPath(recordsDir: _recordsDir(vaultRoot), id: id));

    if (!file.existsSync()) {
      throw VaultNotFoundException('Record not found: ${file.path}');
    }

    return _readFromFile(file: file, expectedId: id);
  }

  Record update({
    required Directory vaultRoot,
    required String id,
    String? type,
    List<String>? tags,
    String? bodyMarkdown,
  }) {
    final existing = read(vaultRoot: vaultRoot, id: id);
    final now = clock.nowUtc().toIso8601String();

    final updated = existing.copyWith(
      updatedAtUtc: now,
      type: type,
      tags: tags,
      bodyMarkdown: bodyMarkdown,
    );

    final file = File(_recordPath(recordsDir: _recordsDir(vaultRoot), id: id));

    // P23: atomic write (temp -> flush -> rename)
    _writeStringAtomicSync(file, codec.encode(updated));

    return updated;
  }

  /// Soft-delete: move from <vault>/records -> <vault>/trash
  void deleteRecord({required Directory vaultRoot, required String recordId}) {
    final src = File(
      _recordPath(recordsDir: _recordsDir(vaultRoot), id: recordId),
    );
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

  /// Restore: move from <vault>/trash -> <vault>/records
  void restoreRecord({required Directory vaultRoot, required String recordId}) {
    final src = File(
      _recordPath(recordsDir: _trashDir(vaultRoot), id: recordId),
    );
    if (!src.existsSync()) {
      throw VaultNotFoundException('Trashed record not found: ${src.path}');
    }

    final recordsDir = _ensureRecordsDir(vaultRoot);
    final dst = File(_recordPath(recordsDir: recordsDir, id: recordId));
    if (dst.existsSync()) {
      throw VaultInvalidException(
        'Active records already contain id: ${dst.path}',
      );
    }

    src.renameSync(dst.path);
  }

  // ---------- dirs / paths ----------

  Directory _recordsDir(Directory vaultRoot) =>
      Directory(p.join(vaultRoot.path, recordsDirName));

  Directory _trashDir(Directory vaultRoot) =>
      Directory(p.join(vaultRoot.path, trashDirName));

  Directory _ensureRecordsDir(Directory vaultRoot) {
    _assertVaultRootExists(vaultRoot);

    final dir = _recordsDir(vaultRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Directory _ensureTrashDir(Directory vaultRoot) {
    _assertVaultRootExists(vaultRoot);

    final dir = _trashDir(vaultRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  void _assertVaultRootExists(Directory vaultRoot) {
    if (!vaultRoot.existsSync()) {
      throw VaultNotFoundException(
        'Vault root does not exist: ${vaultRoot.path}',
      );
    }
  }

  String _recordPath({required Directory recordsDir, required String id}) {
    return p.join(recordsDir.path, '$id.md');
  }

  // ---------- helpers ----------

  Record _readFromFile({required File file, required String expectedId}) {
    final content = file.readAsStringSync();
    final record = codec.decode(content);

    if (record.id != expectedId) {
      throw VaultInvalidException(
        'Record id mismatch: filename=$expectedId frontmatter=${record.id}',
      );
    }

    return record;
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

      return line; // fallback: first non-empty line
    }

    return '(untitled)';
  }

  // P23: atomic write helper (temp -> flush -> rename).
  void _writeStringAtomicSync(File target, String text) {
    target.parent.createSync(recursive: true);

    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    tmp.writeAsStringSync(text, flush: true);
    tmp.renameSync(target.path);
  }
}
