import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/vault/vault_encryption_metadata_service.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

void main() {
  group('VaultEncryptionMetadataService (P23 redundancy)', () {
    late Directory tmpDir;
    late VaultEncryptionMetadataService svc;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('thpitze_encmeta_');
      svc = VaultEncryptionMetadataService();
    });

    tearDown(() {
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    });

    VaultEncryptionInfo enabledInfo() {
      // Minimal valid enabled v1 info.
      return VaultEncryptionInfo.enabledV1(
        saltB64: base64Encode(List<int>.generate(16, (i) => i + 1)),
        kdfParams: const VaultKdfParamsV1(
          memoryKiB: 65536,
          iterations: 3,
          parallelism: 2,
        ),
        keyCheckB64: base64Encode(utf8.encode('dummy_keycheck')),
      );
    }

    File primaryFile() => File(
          '${tmpDir.path}${Platform.pathSeparator}'
          '${VaultEncryptionMetadataService.fileName}',
        );

    File backupFile() => File(
          '${tmpDir.path}${Platform.pathSeparator}'
          '${VaultEncryptionMetadataService.backupFileName}',
        );

    test('save() writes both encryption.json and encryption.json.bak', () async {
      final info = enabledInfo();

      await svc.save(vaultRoot: tmpDir, info: info);

      expect(primaryFile().existsSync(), isTrue);
      expect(backupFile().existsSync(), isTrue);

      final loaded1 = svc.loadOrDefault(vaultRoot: tmpDir);
      expect(loaded1.isEnabled, isTrue);
      expect(loaded1.version, 1);
      expect(loaded1.saltB64, info.saltB64);
      expect(loaded1.keyCheckB64, info.keyCheckB64);

      final rawBak = backupFile().readAsStringSync();
      final decodedBak = jsonDecode(rawBak);
      expect(decodedBak, isA<Map<String, dynamic>>());
      final bakInfo =
          VaultEncryptionInfo.fromJson(decodedBak as Map<String, dynamic>);
      expect(bakInfo.saltB64, info.saltB64);
      expect(bakInfo.keyCheckB64, info.keyCheckB64);
    });

    test('corrupt primary => load uses backup and restores primary', () async {
      final info = enabledInfo();
      await svc.save(vaultRoot: tmpDir, info: info);

      primaryFile().writeAsStringSync('THIS IS NOT JSON', flush: true);

      final loaded = svc.loadOrDefault(vaultRoot: tmpDir);
      expect(loaded.isEnabled, isTrue);
      expect(loaded.saltB64, info.saltB64);

      final restoredText = primaryFile().readAsStringSync();
      final restoredDecoded = jsonDecode(restoredText);
      expect(restoredDecoded, isA<Map<String, dynamic>>());

      final restoredInfo = VaultEncryptionInfo.fromJson(
        restoredDecoded as Map<String, dynamic>,
      );
      expect(restoredInfo.saltB64, info.saltB64);
      expect(restoredInfo.keyCheckB64, info.keyCheckB64);
    });

    test('corrupt primary + corrupt backup => throws VaultInvalidException',
        () async {
      final info = enabledInfo();
      await svc.save(vaultRoot: tmpDir, info: info);

      primaryFile().writeAsStringSync('NOT JSON', flush: true);
      backupFile().writeAsStringSync('ALSO NOT JSON', flush: true);

      expect(
        () => svc.loadOrDefault(vaultRoot: tmpDir),
        throwsA(isA<VaultInvalidException>()),
      );
    });

    test(
        'missing primary => returns VaultEncryptionInfo.none (even if backup exists)',
        () async {
      final info = enabledInfo();
      await svc.save(vaultRoot: tmpDir, info: info);

      primaryFile().deleteSync();

      final loaded = svc.loadOrDefault(vaultRoot: tmpDir);
      expect(loaded, const VaultEncryptionInfo.none());
    });
  });
}
