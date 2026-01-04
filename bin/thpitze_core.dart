// bin/thpitze_core.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:thpitze_main/core/core.dart';
import 'package:thpitze_main/core/records/encrypted_record_service.dart';
import 'package:thpitze_main/core/security/vault_crypto_context.dart';

Future<void> main(List<String> args) async {
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
      print('encrypted: ${ctx.crypto?.isEncrypted ?? false}');
      print('locked:    ${ctx.crypto?.isLocked ?? false}');
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
        tags: const ['cli'],
        bodyMarkdown: '# Hello\n\nThis is a codec roundtrip test.\n',
      );

      final encoded = codec.encode(r);
      final decoded = codec.decode(encoded);

      print('codec encode/decode ok');
      print('id: ${decoded.id}');
      print('type: ${decoded.type}');
      print('tags: ${decoded.tags}');
      print('body:\n${decoded.bodyMarkdown}');
      return;
    }

    // ------------------------------------------------------------
    // RECORD FILESYSTEM COMMANDS
    // ------------------------------------------------------------

    if (cmd == 'record-create') {
      final ctx = _openContext(dir, vaultService);

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);
        final service = EncryptedRecordService(codec: RecordCodec(), clock: ctx.clock);

        final now = ctx.clock.nowUtc().toIso8601String();
        final record = Record(
          id: const Uuid().v4(),
          createdAtUtc: now,
          updatedAtUtc: now,
          type: 'note',
          tags: const ['cli'],
          bodyMarkdown: '# New record\n\nCreated from CLI.\n',
        );

        final created = await service.create(vaultRoot: ctx.vaultRoot, crypto: crypto, record: record);

        print('Record created (encrypted)');
        print('id: ${created.id}');
        print('path: ${p.join(ctx.vaultRoot.path, 'records', '${created.id}.md')}');
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);

        final record = service.create(
          vaultRoot: ctx.vaultRoot,
          type: 'note',
          tags: ['cli'],
          bodyMarkdown: '# New record\n\nCreated from CLI.\n',
        );

        print('Record created');
        print('id: ${record.id}');
        print(
          'path: ${ctx.vaultRoot.path}${Platform.pathSeparator}records'
          '${Platform.pathSeparator}${record.id}.md',
        );
        return;
      }
    }

    if (cmd == 'record-read') {
      if (args.length < 3) {
        stderr.writeln('Missing record id');
        exit(64);
      }

      final recordId = args[2];
      final ctx = _openContext(dir, vaultService);

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);
        final service = EncryptedRecordService(codec: RecordCodec(), clock: ctx.clock);

        final record = await service.read(vaultRoot: ctx.vaultRoot, crypto: crypto, id: recordId);

        print('Record read (encrypted)');
        print('id: ${record.id}');
        print('createdAtUtc: ${record.createdAtUtc}');
        print('updatedAtUtc: ${record.updatedAtUtc}');
        print('type: ${record.type}');
        print('tags: ${record.tags}');
        print('body:\n${record.bodyMarkdown}');
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);
        final record = service.read(vaultRoot: ctx.vaultRoot, id: recordId);

        print('Record read');
        print('id: ${record.id}');
        print('createdAtUtc: ${record.createdAtUtc}');
        print('updatedAtUtc: ${record.updatedAtUtc}');
        print('type: ${record.type}');
        print('tags: ${record.tags}');
        print('body:\n${record.bodyMarkdown}');
        return;
      }
    }

    if (cmd == 'record-update') {
      if (args.length < 3) {
        stderr.writeln('Missing record id');
        exit(64);
      }

      final recordId = args[2];
      final ctx = _openContext(dir, vaultService);

      final appendedLine =
          '\n- updated via CLI at ${ctx.clock.nowUtc().toIso8601String()}\n';

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);
        final service = EncryptedRecordService(codec: RecordCodec(), clock: ctx.clock);

        final before = await service.read(vaultRoot: ctx.vaultRoot, crypto: crypto, id: recordId);

        final newBody = before.bodyMarkdown + appendedLine;
        final newTags = <String>{...before.tags, 'updated'}.toList()..sort();
        final now = ctx.clock.nowUtc().toIso8601String();

        final updated = Record(
          id: before.id,
          createdAtUtc: before.createdAtUtc,
          updatedAtUtc: now,
          type: before.type,
          tags: newTags,
          bodyMarkdown: newBody,
        );

        final after = await service.update(
          vaultRoot: ctx.vaultRoot,
          crypto: crypto,
          id: recordId,
          updated: updated,
        );

        print('Record updated (encrypted)');
        print('id: ${after.id}');
        print('createdAtUtc (before): ${before.createdAtUtc}');
        print('createdAtUtc (after):  ${after.createdAtUtc}');
        print('updatedAtUtc (before): ${before.updatedAtUtc}');
        print('updatedAtUtc (after):  ${after.updatedAtUtc}');
        print('tags (after): ${after.tags}');
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);

        final before = service.read(vaultRoot: ctx.vaultRoot, id: recordId);

        final newBody = before.bodyMarkdown + appendedLine;
        final newTags = <String>{...before.tags, 'updated'}.toList()..sort();

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
    }

    if (cmd == 'record-list') {
      final ctx = _openContext(dir, vaultService);

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);
        final service = EncryptedRecordService(codec: RecordCodec(), clock: ctx.clock);

        final headers = await service.listHeaders(vaultRoot: ctx.vaultRoot, crypto: crypto);

        print('Records: ${headers.length} (encrypted)');
        for (final h in headers) {
          final shortId = _shortId(h.id);
          final tags = h.tags.isEmpty ? '-' : h.tags.join(',');
          print('${h.updatedAtUtc} | ${h.type} | ${h.title} | tags=$tags | $shortId');
        }
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);
        final headers = service.listHeaders(vaultRoot: ctx.vaultRoot);

        print('Records: ${headers.length}');
        for (final h in headers) {
          final shortId = _shortId(h.id);
          final tags = h.tags.isEmpty ? '-' : h.tags.join(',');
          print('${h.updatedAtUtc} | ${h.type} | ${h.title} | tags=$tags | $shortId');
        }
        return;
      }
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

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);
        final service = EncryptedRecordService(codec: RecordCodec(), clock: ctx.clock);

        final headers = await service.listHeaders(vaultRoot: ctx.vaultRoot, crypto: crypto);
        final match = _matchByPrefix(headers.map((h) => h.id), provided);

        if (match == null) {
          stderr.writeln('No record matches prefix/id: "$provided"');
          exit(2);
        }

        service.deleteRecord(vaultRoot: ctx.vaultRoot, recordId: match);
        print('Record moved to trash (encrypted): $match');
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);

        final headers = service.listHeaders(vaultRoot: ctx.vaultRoot);
        final match = _matchByPrefix(headers.map((h) => h.id), provided);

        if (match == null) {
          stderr.writeln('No record matches prefix/id: "$provided"');
          exit(2);
        }

        service.deleteRecord(vaultRoot: ctx.vaultRoot, recordId: match);
        print('Record moved to trash: $match');
        return;
      }
    }

    if (cmd == 'trash-list') {
      final ctx = _openContext(dir, vaultService);

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);

        final headers = await _listTrashedHeadersEncrypted(
          vaultRoot: ctx.vaultRoot,
          crypto: crypto,
          clock: ctx.clock,
        );

        print('Trash: ${headers.length} (encrypted)');
        for (final h in headers) {
          final shortId = _shortId(h.id);
          final tags = h.tags.isEmpty ? '-' : h.tags.join(',');
          print('${h.updatedAtUtc} | ${h.type} | ${h.title} | tags=$tags | $shortId');
        }
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);
        final headers = service.listTrashedHeaders(vaultRoot: ctx.vaultRoot);

        print('Trash: ${headers.length}');
        for (final h in headers) {
          final shortId = _shortId(h.id);
          final tags = h.tags.isEmpty ? '-' : h.tags.join(',');
          print('${h.updatedAtUtc} | ${h.type} | ${h.title} | tags=$tags | $shortId');
        }
        return;
      }
    }

    if (cmd == 'record-restore') {
      if (args.length < 3) {
        stderr.writeln('Missing record id or prefix');
        exit(64);
      }

      final provided = args[2].trim();
      final ctx = _openContext(dir, vaultService);

      if (_isEncrypted(ctx.crypto)) {
        final crypto = _requireUnlocked(ctx.crypto);
        final service = EncryptedRecordService(codec: RecordCodec(), clock: ctx.clock);

        final trashed = await _listTrashedHeadersEncrypted(
          vaultRoot: ctx.vaultRoot,
          crypto: crypto,
          clock: ctx.clock,
        );
        final match = _matchByPrefix(trashed.map((h) => h.id), provided);

        if (match == null) {
          stderr.writeln('No trashed record matches prefix/id: "$provided"');
          exit(2);
        }

        service.restoreRecord(vaultRoot: ctx.vaultRoot, recordId: match);
        print('Record restored (encrypted): $match');
        return;
      } else {
        final service = RecordService(codec: RecordCodec(), clock: ctx.clock);

        final trashed = service.listTrashedHeaders(vaultRoot: ctx.vaultRoot);
        final match = _matchByPrefix(trashed.map((h) => h.id), provided);

        if (match == null) {
          stderr.writeln('No trashed record matches prefix/id: "$provided"');
          exit(2);
        }

        service.restoreRecord(vaultRoot: ctx.vaultRoot, recordId: match);
        print('Record restored: $match');
        return;
      }
    }

    stderr.writeln('Unknown command: $cmd');
    _printUsage();
    exit(64);
  } catch (e, st) {
    stderr.writeln('Error: $e');
    stderr.writeln(st);
    exit(1);
  }
}

bool _isEncrypted(VaultCryptoContext? crypto) => crypto != null && crypto.isEncrypted;

VaultCryptoContext _requireUnlocked(VaultCryptoContext? crypto) {
  if (crypto == null || !crypto.isEncrypted) {
    throw StateError('Internal: expected encrypted VaultCryptoContext.');
  }
  if (crypto.isLocked) {
    throw StateError(
      'Vault is encrypted but locked. Set THPITZE_PASSWORD in the environment for CLI record commands.',
    );
  }
  return crypto;
}

Future<List<RecordHeader>> _listTrashedHeadersEncrypted({
  required Directory vaultRoot,
  required VaultCryptoContext crypto,
  required Clock clock,
}) async {
  final trashDir = Directory(p.join(vaultRoot.path, 'trash'));
  if (!trashDir.existsSync()) return <RecordHeader>[];

  final codec = RecordCodec();

  final headers = <RecordHeader>[];
  for (final entity in trashDir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    if (p.extension(entity.path).toLowerCase() != '.md') continue;

    final id = p.basenameWithoutExtension(entity.path).trim();
    if (id.isEmpty) continue;

    final b64 = entity.readAsStringSync();
    final payload = VaultPayloadCodec.decodeB64(b64);

    final plainBytes = await crypto.requireEncryptionService.decrypt(
      info: crypto.requireInfo,
      key: crypto.requireKey,
      payload: payload,
    );

    final content = utf8.decode(plainBytes);
    final record = codec.decode(content);

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

CoreContext _openContext(
  Directory vaultRoot,
  VaultIdentityService vaultIdentityService,
) {
  final bootstrap = CoreBootstrap(
    vaultIdentityService: vaultIdentityService,
    clock: _SystemClock(),
  );

  // Optional: allow supplying password via env var for CLI usage
  final pw = Platform.environment['THPITZE_PASSWORD'];
  return bootstrap.openVault(vaultRoot, password: pw);
}

class _SystemClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

String? _matchByPrefix(Iterable<String> ids, String provided) {
  if (provided.isEmpty) return null;

  // Exact match first
  for (final id in ids) {
    if (id == provided) return id;
  }

  // Prefix match
  final matches = <String>[];
  for (final id in ids) {
    if (id.startsWith(provided)) matches.add(id);
  }

  if (matches.length == 1) return matches.first;
  return null; // none or ambiguous
}

void _printUsage() {
  final exe = p.basename(Platform.resolvedExecutable);
  print('Usage: $exe bin/thpitze_core.dart <command> <vaultPath> [args]');
  print('');
  print('Vault:');
  print('  init <vaultPath>');
  print('  validate <vaultPath>');
  print('  open <vaultPath>');
  print('');
  print('Records:');
  print('  codec-test <vaultPath>');
  print('  record-create <vaultPath>');
  print('  record-read <vaultPath> <recordId>');
  print('  record-update <vaultPath> <recordId>');
  print('  record-list <vaultPath>');
  print('  record-delete <vaultPath> <recordIdOrPrefix>');
  print('  trash-list <vaultPath>');
  print('  record-restore <vaultPath> <recordIdOrPrefix>');
  print('');
  print('Env:');
  print('  THPITZE_PASSWORD=<pw>   (required for encrypted vault record commands)');
}

