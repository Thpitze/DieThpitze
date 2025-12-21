// bin/thpitze_core.dart
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:thpitze_main/core/core.dart';

import 'package:path/path.dart' as p;

void main(List<String> args) {
  if (args.length < 2) {
    _printUsage();
    exit(64);
  }

  final cmd = args[0];
  final path = args[1];
  final dir = Directory(path);

  final vaultService = VaultIdentityService();

  try {
    // ------------------------------------------------------------
    // VAULT COMMANDS
    // ------------------------------------------------------------

    if (cmd == 'init') {
      final info = vaultService.initVault(dir);
      print('Vault initialized');
      print(info.toJsonString(pretty: true));
      return;
    }

    if (cmd == 'validate') {
      final info = vaultService.validateVault(dir);
      print('Vault valid');
      print(info.toJsonString(pretty: true));
      return;
    }

    if (cmd == 'open') {
      final ctx = _openContext(dir, vaultService);
      print('CoreContext created');
      print('vaultRoot: ${ctx.vaultRoot.path}');
      print('vaultId:   ${ctx.vaultInfo.vaultId}');
      print('schema:    ${ctx.vaultInfo.schemaVersionValue}');
      print('nowUtc:    ${ctx.clock.nowUtc().toIso8601String()}');
      return;
    }

    // ------------------------------------------------------------
    // RECORD FORMAT TEST (no filesystem)
    // ------------------------------------------------------------

    if (cmd == 'codec-test') {
      final codec = RecordCodec();
      final now = DateTime.now().toUtc().toIso8601String();

      final r = Record(
        id: const Uuid().v4(),
        createdAtUtc: now,
        updatedAtUtc: now,
        type: 'note',
        tags: ['alpha', 'beta'],
        bodyMarkdown: '# Hello\n\nThis is a test.\n',
      );

      final encoded = codec.encode(r);
      print('=== ENCODED RECORD FILE ===');
      print(encoded);

      final decoded = codec.decode(encoded);
      print('=== DECODED SUMMARY ===');
      print('id: ${decoded.id}');
      print('type: ${decoded.type}');
      print('tags: ${decoded.tags}');
      print('body: ${_firstN(decoded.bodyMarkdown, 40)}');
      return;
    }

    // ------------------------------------------------------------
    // RECORD FILESYSTEM COMMANDS
    // ------------------------------------------------------------

    if (cmd == 'record-create') {
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final record = service.create(
        vaultRoot: ctx.vaultRoot,
        type: 'note',
        tags: ['cli'],
        bodyMarkdown: '# New record\n\nCreated from CLI.\n',
      );

      print('Record created');
      print('id: ${record.id}');
      print('path: ${ctx.vaultRoot.path}${Platform.pathSeparator}records'
          '${Platform.pathSeparator}${record.id}.md');
      return;
    }

    if (cmd == 'record-read') {
      if (args.length < 3) {
        stderr.writeln('Missing record id');
        exit(64);
      }

      final recordId = args[2];
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final record = service.read(
        vaultRoot: ctx.vaultRoot,
        id: recordId,
      );

      print('Record read');
      print('id: ${record.id}');
      print('createdAtUtc: ${record.createdAtUtc}');
      print('updatedAtUtc: ${record.updatedAtUtc}');
      print('type: ${record.type}');
      print('tags: ${record.tags}');
      print('body:\n${record.bodyMarkdown}');
      return;
    }

    if (cmd == 'record-update') {
      if (args.length < 3) {
        stderr.writeln('Missing record id');
        exit(64);
      }

      final recordId = args[2];
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final before = service.read(vaultRoot: ctx.vaultRoot, id: recordId);

      final appendedLine =
          '\n- updated via CLI at ${ctx.clock.nowUtc().toIso8601String()}\n';

      final newBody = before.bodyMarkdown + appendedLine;

      final newTags = <String>{
        ...before.tags,
        'updated',
      }.toList()
        ..sort();

      final after = service.update(
        vaultRoot: ctx.vaultRoot,
        id: recordId,
        tags: newTags,
        bodyMarkdown: newBody,
      );

      print('Record updated');
      print('id: ${after.id}');
      print('createdAtUtc (before): ${before.createdAtUtc}');
      print('createdAtUtc (after):  ${after.createdAtUtc}');
      print('updatedAtUtc (before): ${before.updatedAtUtc}');
      print('updatedAtUtc (after):  ${after.updatedAtUtc}');
      print('tags (after): ${after.tags}');
      return;
    }

    if (cmd == 'record-list') {
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final headers = service.listHeaders(vaultRoot: ctx.vaultRoot);

      print('Records: ${headers.length}');
      for (final h in headers) {
        final shortId = _shortId(h.id);
        final tags = h.tags.isEmpty ? '-' : h.tags.join(',');
        print('${h.updatedAtUtc} | ${h.type} | ${h.title} | tags=$tags | $shortId');
      }
      return;
    }

    // ------------------------------------------------------------
    // TRASH / DELETE / RESTORE (soft delete)
    // ------------------------------------------------------------

    if (cmd == 'record-delete') {
      if (args.length < 3) {
        stderr.writeln('Missing record id or prefix');
        exit(64);
      }

      final provided = args[2].trim();
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final resolvedId = _resolveRecordIdInRecords(
        vaultRoot: ctx.vaultRoot,
        idOrPrefix: provided,
      );

      service.deleteRecord(vaultRoot: ctx.vaultRoot, recordId: resolvedId);

      print('Record deleted (moved to trash)');
      print('id: $resolvedId');
      print('from: ${ctx.vaultRoot.path}${Platform.pathSeparator}records'
          '${Platform.pathSeparator}$resolvedId.md');
      print('to:   ${ctx.vaultRoot.path}${Platform.pathSeparator}trash'
          '${Platform.pathSeparator}$resolvedId.md');
      return;
    }

    if (cmd == 'trash-list') {
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final headers = service.listTrashedHeaders(vaultRoot: ctx.vaultRoot);

      print('Trash: ${headers.length}');
      for (final h in headers) {
        final shortId = _shortId(h.id);
        final tags = h.tags.isEmpty ? '-' : h.tags.join(',');
        print('${h.updatedAtUtc} | ${h.type} | ${h.title} | tags=$tags | $shortId');
      }
      return;
    }
    if (cmd == 'trash-restore') {
      if (args.length < 3) {
        stderr.writeln('Missing record id or prefix');
        exit(64);
      }

      final provided = args[2].trim();
      final ctx = _openContext(dir, vaultService);

      final service = RecordService(
        codec: RecordCodec(),
        clock: ctx.clock,
      );

      final resolvedId = _resolveRecordIdInTrash(
        vaultRoot: ctx.vaultRoot,
        idOrPrefix: provided,
      );

      service.restoreRecord(vaultRoot: ctx.vaultRoot, recordId: resolvedId);

      print('Record restored (moved to records)');
      print('id: $resolvedId');
      print('from: ${ctx.vaultRoot.path}${Platform.pathSeparator}trash'
          '${Platform.pathSeparator}$resolvedId.md');
      print('to:   ${ctx.vaultRoot.path}${Platform.pathSeparator}records'
          '${Platform.pathSeparator}$resolvedId.md');
      return;
    }

    _printUsage();
    exit(64);
  } on VaultException catch (e) {
    stderr.writeln('ERROR: ${e.message}');
    exit(1);
  }
}

CoreContext _openContext(
  Directory vaultDir,
  VaultIdentityService vaultService,
) {
  final bootstrap = CoreBootstrap(
    vaultIdentityService: vaultService,
    clock: SystemClock(),
  );
  return bootstrap.openVault(vaultDir);
}

String _resolveRecordIdInRecords({
  required Directory vaultRoot,
  required String idOrPrefix,
}) {
  return _resolveRecordIdInDir(
    dir: Directory(p.join(vaultRoot.path, 'records')),
    idOrPrefix: idOrPrefix,
    label: 'records',
  );
}

String _resolveRecordIdInTrash({
  required Directory vaultRoot,
  required String idOrPrefix,
}) {
  return _resolveRecordIdInDir(
    dir: Directory(p.join(vaultRoot.path, 'trash')),
    idOrPrefix: idOrPrefix,
    label: 'trash',
  );
}

String _resolveRecordIdInDir({
  required Directory dir,
  required String idOrPrefix,
  required String label,
}) {
  final needle = idOrPrefix.trim();
  if (needle.isEmpty) {
    throw VaultInvalidException('Empty record id/prefix');
  }

  // If it looks like a full UUID, accept as-is.
  if (needle.length >= 36 && needle.contains('-')) {
    return needle;
  }

  if (!dir.existsSync()) {
    throw VaultNotFoundException('Directory does not exist: ${dir.path}');
  }

  final matches = <String>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.toLowerCase().endsWith('.md')) continue;

    final id = p.basenameWithoutExtension(entity.path);
    if (id.startsWith(needle)) {
      matches.add(id);
    }
  }

  if (matches.isEmpty) {
    throw VaultNotFoundException('No $label record matches prefix: $needle');
  }

  matches.sort();

  if (matches.length > 1) {
    final shown = matches.take(10).map(_shortId).join(', ');
    throw VaultInvalidException(
      'Ambiguous prefix "$needle" in $label. Matches: $shown',
    );
  }

  return matches.single;
}

String _shortId(String id) {
  if (id.length <= 8) return id;
  return id.substring(0, 8);
}

String _firstN(String s, int n) {
  if (s.length <= n) return s;
  return '${s.substring(0, n)}...';
}

void _printUsage() {
  print('Usage:');
  print('  dart run bin/thpitze_core.dart init <vault_path>');
  print('  dart run bin/thpitze_core.dart validate <vault_path>');
  print('  dart run bin/thpitze_core.dart open <vault_path>');
  print('  dart run bin/thpitze_core.dart codec-test <anything>');
  print('  dart run bin/thpitze_core.dart record-create <vault_path>');
  print('  dart run bin/thpitze_core.dart record-read <vault_path> <record_id>');
  print('  dart run bin/thpitze_core.dart record-update <vault_path> <record_id>');
  print('  dart run bin/thpitze_core.dart record-list <vault_path>');
  print('  dart run bin/thpitze_core.dart record-delete <vault_path> <id_or_prefix>');
  print('  dart run bin/thpitze_core.dart trash-list <vault_path>');
  print('  dart run bin/thpitze_core.dart trash-restore <vault_path> <id_or_prefix>');
}
