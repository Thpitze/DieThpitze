import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/vault/vault_encryption_info.dart';
import 'package:thpitze_main/core/vault/vault_encryption_metadata_service.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

void main() {
  group('VaultEncryptionMetadataService', () {
    VaultEncryptionInfo enabledInfo() {
      return const VaultEncryptionInfo.enabledV1(
        saltB64: 'AAAAAAAAAAAAAAAAAAAAAA==',
        kdfParams: VaultKdfParamsV1(
          memoryKiB: 65536,
          iterations: 3,
          parallelism: 1,
        ),
        keyCheckB64: 'AQIDBAUGBwgJCgsMDQ4PEA==',
      );
    }

    test('missing encryption.json => none()', () async {
      final dir = await Directory.systemTemp.createTemp('thpitze_enc_test_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final svc = VaultEncryptionMetadataService();
      final info = svc.loadOrDefault(vaultRoot: dir);

      expect(info.state, 'none');
      expect(info.version, isNull);
      expect(info.isEnabled, isFalse);
    });

    test('save(enabledV1) then load => enabled', () async {
      final dir = await Directory.systemTemp.createTemp('thpitze_enc_test_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final svc = VaultEncryptionMetadataService();

      await svc.save(vaultRoot: dir, info: enabledInfo());

      final loaded = svc.loadOrDefault(vaultRoot: dir);

      expect(loaded.isEnabled, isTrue);
      expect(loaded.version, 1);
      expect(loaded.schema, VaultEncryptionInfo.schemaV1);
      expect((loaded.cipher ?? '').isNotEmpty, isTrue);
      expect((loaded.kdf ?? '').isNotEmpty, isTrue);
      expect((loaded.saltB64 ?? '').isNotEmpty, isTrue);
      expect(loaded.kdfParams, isNotNull);
      expect((loaded.keyCheckB64 ?? '').isNotEmpty, isTrue);

      final f = File(
        '${dir.path}${Platform.pathSeparator}${VaultEncryptionMetadataService.fileName}',
      );
      expect(f.existsSync(), isTrue);
    });

    test('invalid schema => VaultInvalidException', () async {
      final dir = await Directory.systemTemp.createTemp('thpitze_enc_test_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final f = File(
        '${dir.path}${Platform.pathSeparator}${VaultEncryptionMetadataService.fileName}',
      );
      f.writeAsStringSync(
        '{"schema":"bad.schema","state":"enabled","version":1,"cipher":"AES-256-GCM","kdf":"Argon2id","saltB64":"AAAAAAAAAAAAAAAAAAAAAA==","kdfParams":{"memoryKiB":65536,"iterations":3,"parallelism":1},"keyCheckB64":"AQIDBAUGBwgJCgsMDQ4PEA=="}',
      );

      final svc = VaultEncryptionMetadataService();

      expect(
        () => svc.loadOrDefault(vaultRoot: dir),
        throwsA(isA<VaultInvalidException>()),
      );
    });

    test('enabled without version => VaultInvalidException', () async {
      final dir = await Directory.systemTemp.createTemp('thpitze_enc_test_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final f = File(
        '${dir.path}${Platform.pathSeparator}${VaultEncryptionMetadataService.fileName}',
      );
      f.writeAsStringSync(
        '{"schema":"thpitze.vault_encryption.v1","state":"enabled","cipher":"AES-256-GCM","kdf":"Argon2id","saltB64":"AAAAAAAAAAAAAAAAAAAAAA==","kdfParams":{"memoryKiB":65536,"iterations":3,"parallelism":1},"keyCheckB64":"AQIDBAUGBwgJCgsMDQ4PEA=="}',
      );

      final svc = VaultEncryptionMetadataService();

      expect(
        () => svc.loadOrDefault(vaultRoot: dir),
        throwsA(isA<VaultInvalidException>()),
      );
    });
  });
}
