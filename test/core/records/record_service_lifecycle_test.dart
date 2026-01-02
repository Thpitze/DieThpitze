import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/records/record_codec.dart';
import 'package:thpitze_main/core/records/record_service.dart';
import 'package:thpitze_main/core/time/clock.dart';

class _FixedClock implements Clock {
  DateTime _t;
  _FixedClock(this._t);

  @override
  DateTime nowUtc() => _t;

  void advanceSeconds(int s) {
    _t = _t.add(Duration(seconds: s));
  }
}

void main() {
  group('RecordService lifecycle', () {
    test('create -> read -> update roundtrip', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'thpitze_record_service_',
      );
      addTearDown(() async {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final clock = _FixedClock(DateTime.utc(2025, 1, 1, 0, 0, 0));
      final service = RecordService(codec: RecordCodec(), clock: clock);

      final created = service.create(
        vaultRoot: tmp,
        type: 'note',
        tags: const ['a', 'b'],
        bodyMarkdown: '# Title\n\nBody\n',
      );

      final loaded = service.read(vaultRoot: tmp, id: created.id);
      expect(loaded.id, created.id);
      expect(loaded.type, 'note');
      expect(loaded.tags, ['a', 'b']);
      expect(loaded.bodyMarkdown, contains('Title'));

      clock.advanceSeconds(5);

      final updated = service.update(
        vaultRoot: tmp,
        id: created.id,
        tags: const ['b', 'c'],
        bodyMarkdown: '# Title\n\nUpdated\n',
      );

      final reloaded = service.read(vaultRoot: tmp, id: created.id);
      expect(reloaded.id, created.id);
      expect(reloaded.tags, ['b', 'c']);
      expect(reloaded.bodyMarkdown, contains('Updated'));

      // updatedAtUtc changed
      expect(updated.updatedAtUtc, isNot(equals(created.updatedAtUtc)));
    });

    test('delete -> trashed headers -> restore', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'thpitze_record_service_',
      );
      addTearDown(() async {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final clock = _FixedClock(DateTime.utc(2025, 1, 1, 0, 0, 0));
      final service = RecordService(codec: RecordCodec(), clock: clock);

      final r = service.create(
        vaultRoot: tmp,
        type: 'note',
        tags: const ['x'],
        bodyMarkdown: 'hello',
      );

      service.deleteRecord(vaultRoot: tmp, recordId: r.id);

      final trashed = service.listTrashedHeaders(vaultRoot: tmp);
      expect(trashed.length, 1);
      expect(trashed.first.id, r.id);

      service.restoreRecord(vaultRoot: tmp, recordId: r.id);

      final trashedAfter = service.listTrashedHeaders(vaultRoot: tmp);
      expect(trashedAfter, isEmpty);

      final active = service.listHeaders(vaultRoot: tmp);
      expect(active.any((h) => h.id == r.id), isTrue);
    });

    test('listHeaders sorts by updatedAtUtc desc', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'thpitze_record_service_',
      );
      addTearDown(() async {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final clock = _FixedClock(DateTime.utc(2025, 1, 1, 0, 0, 0));
      final service = RecordService(codec: RecordCodec(), clock: clock);

      final a = service.create(vaultRoot: tmp, bodyMarkdown: 'A');

      clock.advanceSeconds(10);

      final b = service.create(vaultRoot: tmp, bodyMarkdown: 'B');

      final headers = service.listHeaders(vaultRoot: tmp);
      expect(headers.length, 2);
      expect(headers.first.id, b.id);
      expect(headers.last.id, a.id);
    });
  });
}
