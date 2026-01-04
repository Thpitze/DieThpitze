import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/blobs/blob_storage.dart';

void main() {
  group('BlobStorage atomic writes', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('thpitze_blob_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('putBytes writes final blob and leaves no temp files behind', () async {
      final storage = BlobStorage(vaultRoot: tmpDir);

      final bytes = Uint8List.fromList(List<int>.generate(256 * 1024, (i) => i & 0xFF));
      final digest = sha256.convert(bytes).toString();

      final ref = await storage.putBytes(bytes, mimeType: 'application/octet-stream');
      expect(ref.sha256, digest);

      // File must exist
      final exists = await storage.exists(digest);
      expect(exists, isTrue);

      // Readback must match
      final readback = await storage.readBytes(digest);
      expect(readback, bytes);

      // Ensure no temp files remain under blobs/
      final blobsDir = Directory('${tmpDir.path}${Platform.pathSeparator}blobs');
      expect(blobsDir.existsSync(), isTrue);

      final tmpLeftovers = <FileSystemEntity>[];
      await for (final e in blobsDir.list(recursive: true, followLinks: false)) {
        final p = e.path;
        if (p.contains('.tmp.')) {
          tmpLeftovers.add(e);
        }
      }

      expect(tmpLeftovers, isEmpty);
    });
  });
}
