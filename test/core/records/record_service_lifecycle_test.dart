import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/records/record_codec.dart';
import 'package:thpitze_main/core/records/record_service.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

class _FixedClock implements Clock {
  DateTime _now;
  _FixedClock(this._now);

  @override
  DateTime nowUtc() => _now.toUtc();

  void advance(Duration d) {
    _now = _now.add(d);
  }
}

void main() {
  group('RecordService lifecycle (filesystem)', () {
    late Directory tempRoot;
    late Directory vaultRoot;
    late _FixedClock clock;
    late RecordService service;

    // Contract: RecordCodec / RecordService may introduce leading newlines in the body.
    // We lock semantics by ignoring ONLY leading '\n' (not trailing spaces, not internal newlines).
    String stripLeadingNewlines(String s) => s.replaceFirst(RegExp(r'^\n+'), '');

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('thpitze_recordsvc_');
      vaultRoot = Directory('${tempRoot.path}${Platform.pathSeparator}vault')
        ..createSync(recursive: true);

      clock = _FixedClock(DateTime.utc(2025, 12, 21, 12, 0, 0));
      service = RecordService(codec: RecordCodec(), clock: clock);
    });

    tearDown(() async {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup.
      }
    });

    test('create → deleteRecord → restoreRecord moves file records/ ↔ trash/', () {
      final created = service.create(
        vaultRoot: vaultRoot,
        type: 'note',
        tags: const ['test'],
        bodyMarkdown: 'hello\n',
      );

      final id = created.id;
      expect(id, isNotEmpty);

      final recordsFile = File(
        '${vaultRoot.path}${Platform.pathSeparator}'
        '${RecordService.recordsDirName}${Platform.pathSeparator}$id.md',
      );
      final trashFile = File(
        '${vaultRoot.path}${Platform.pathSeparator}'
        '${RecordService.trashDirName}${Platform.pathSeparator}$id.md',
      );

      expect(recordsFile.existsSync(), isTrue);
      expect(trashFile.existsSync(), isFalse);

      service.deleteRecord(vaultRoot: vaultRoot, recordId: id);
      expect(recordsFile.existsSync(), isFalse);
      expect(trashFile.existsSync(), isTrue);

      service.restoreRecord(vaultRoot: vaultRoot, recordId: id);
      expect(recordsFile.existsSync(), isTrue);
      expect(trashFile.existsSync(), isFalse);

      final reread = service.read(vaultRoot: vaultRoot, id: id);
      expect(reread.id, id);
      expect(reread.type, 'note');
      expect(reread.tags, const ['test']);

      expect(
        stripLeadingNewlines(reread.bodyMarkdown),
        stripLeadingNewlines('hello\n'),
      );
    });

    test('deleteRecord throws if record not found', () {
      expect(
        () => service.deleteRecord(
          vaultRoot: vaultRoot,
          recordId: '00000000-0000-0000-0000-000000000000',
        ),
        throwsA(isA<VaultNotFoundException>()),
      );
    });

    test('restoreRecord throws if trashed record not found', () {
      expect(
        () => service.restoreRecord(
          vaultRoot: vaultRoot,
          recordId: '00000000-0000-0000-0000-000000000000',
        ),
        throwsA(isA<VaultNotFoundException>()),
      );
    });

    test('restoreRecord throws if active record already exists', () {
      final r = service.create(
        vaultRoot: vaultRoot,
        type: 'note',
        tags: const [],
        bodyMarkdown: 'x',
      );

      service.deleteRecord(vaultRoot: vaultRoot, recordId: r.id);

      // Manually create conflicting active file before restore.
      final conflictFile = File(
        '${vaultRoot.path}${Platform.pathSeparator}'
        '${RecordService.recordsDirName}${Platform.pathSeparator}${r.id}.md',
      );
      conflictFile.createSync(recursive: true);
      conflictFile.writeAsStringSync('conflict');

      expect(
        () => service.restoreRecord(vaultRoot: vaultRoot, recordId: r.id),
        throwsA(isA<VaultInvalidException>()),
      );
    });

    test('deleteRecord throws if trash already contains same id', () {
      final r = service.create(
        vaultRoot: vaultRoot,
        type: 'note',
        tags: const [],
        bodyMarkdown: 'x',
      );

      // Create a conflicting trash file manually.
      final trashFile = File(
        '${vaultRoot.path}${Platform.pathSeparator}'
        '${RecordService.trashDirName}${Platform.pathSeparator}${r.id}.md',
      );
      trashFile.createSync(recursive: true);
      trashFile.writeAsStringSync('already in trash');

      expect(
        () => service.deleteRecord(vaultRoot: vaultRoot, recordId: r.id),
        throwsA(isA<VaultInvalidException>()),
      );
    });
  });
}
