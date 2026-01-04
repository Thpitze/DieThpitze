import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:thpitze_main/core/records/encrypted_record_service.dart';
import 'package:thpitze_main/core/records/record.dart';
import 'package:thpitze_main/core/records/record_codec.dart';
import 'package:thpitze_main/core/security/vault_crypto_context.dart';
import 'package:thpitze_main/core/security/vault_encryption_service_impl.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';

class _FixedClock implements Clock {
  final DateTime t;
  _FixedClock(this.t);

  @override
  DateTime nowUtc() => t;
}

Uint8List _randomBytes(int n) {
  final r = Random(1234567); // deterministic for tests
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}

String _normalizeBody(String s) {
  // RecordCodec may normalize body to start with a single leading newline.
  if (s.startsWith('\n')) return s.substring(1);
  return s;
}

void main() {
  group('EncryptedRecordService', () {
    late Directory tmp;
    late EncryptedRecordService svc;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('thpitze_enc_records_');
      svc = EncryptedRecordService(
        codec: RecordCodec(),
        clock: _FixedClock(DateTime.utc(2026, 1, 1)),
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('writes encrypted payload (no plaintext markdown on disk)', () async {
      final encSvc = VaultEncryptionServiceImpl();

      final salt = _randomBytes(16);
      final saltB64 = base64Encode(salt);

      final kdfParams = VaultKdfParamsV1(
        memoryKiB: 64 * 1024,
        iterations: 2,
        parallelism: 1,
      );

      final infoTmp = VaultEncryptionInfo.enabledV1(
        saltB64: saltB64,
        kdfParams: kdfParams,
        keyCheckB64: 'tmp',
      );

      final key = await encSvc.deriveKey(
        info: infoTmp,
        password: 'pw123',
        salt: salt,
      );

      final keyCheckB64 = await encSvc.buildKeyCheckB64(info: infoTmp, key: key);

      final info = VaultEncryptionInfo.enabledV1(
        saltB64: saltB64,
        kdfParams: kdfParams,
        keyCheckB64: keyCheckB64,
      );

      final crypto = VaultCryptoContext.encryptedUnlocked(
        info: info,
        encryptionService: encSvc,
        key: key,
      );

      final record = Record(
        id: 'rec1',
        createdAtUtc: '2026-01-01T00:00:00.000Z',
        updatedAtUtc: '2026-01-01T00:00:00.000Z',
        type: 'note',
        tags: const ['a'],
        bodyMarkdown: '# Hello\nSecret content',
      );

      await svc.create(vaultRoot: tmp, crypto: crypto, record: record);

      final recordsDir = Directory(p.join(tmp.path, 'records'));
      expect(recordsDir.existsSync(), isTrue, reason: 'records/ directory should exist');

      final file = File(p.join(recordsDir.path, 'rec1.md'));
      expect(file.existsSync(), isTrue);

      final onDisk = file.readAsStringSync();

      // Must not contain obvious plaintext fragments.
      expect(onDisk.contains('Secret content'), isFalse);
      expect(onDisk.contains('# Hello'), isFalse);

      // Base64-ish: should be ASCII and reasonably long.
      expect(onDisk.length, greaterThan(40));
      expect(RegExp(r'^[A-Za-z0-9+/=\\r\\n]+$').hasMatch(onDisk), isTrue);

      // Roundtrip works (normalize codec quirks)
      final readBack = await svc.read(vaultRoot: tmp, crypto: crypto, id: 'rec1');
      expect(_normalizeBody(readBack.bodyMarkdown), record.bodyMarkdown);
      expect(readBack.tags, record.tags);
      expect(readBack.type, record.type);
    });
  });
}
