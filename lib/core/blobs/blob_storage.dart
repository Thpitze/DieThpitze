// lib/core/blobs/blob_storage.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'blob_ref.dart';

/// Content-addressed blob storage inside a vault folder.
///
/// Layout: `<vaultRoot>/blobs/sha256/aa/bb/<fullhash>`
class BlobStorage {
  final Directory vaultRoot;

  BlobStorage({required this.vaultRoot});

  Directory get _baseDir => Directory(
    '${vaultRoot.path}${Platform.pathSeparator}blobs'
    '${Platform.pathSeparator}sha256',
  );

  Future<BlobRef> putBytes(Uint8List bytes, {String? mimeType}) async {
    final digest = sha256.convert(bytes);
    final hash = digest.toString(); // lowercase hex
    final size = bytes.length;

    final file = _fileForHash(hash);
    if (await file.exists()) {
      return BlobRef(sha256: hash, sizeBytes: size, mimeType: mimeType);
    }

    await file.parent.create(recursive: true);

    // Atomic write: temp file then rename.
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    await tmp.writeAsBytes(bytes, flush: true);

    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      // If another writer raced and created it, keep the existing blob.
      if (!await file.exists()) rethrow;
      try {
        await tmp.delete();
      } catch (_) {
        // ignore cleanup failure
      }
    }

    return BlobRef(sha256: hash, sizeBytes: size, mimeType: mimeType);
  }

  Future<bool> exists(String sha256Hex) async {
    return _fileForHash(sha256Hex).exists();
  }

  Stream<List<int>> openRead(String sha256Hex) {
    return _fileForHash(sha256Hex).openRead();
  }

  Future<Uint8List> readBytes(String sha256Hex) async {
    final bytes = await _fileForHash(sha256Hex).readAsBytes();
    return Uint8List.fromList(bytes);
  }

  Future<void> delete(String sha256Hex) async {
    // Unsafe without reference counting. Use only for cleanup tools.
    final f = _fileForHash(sha256Hex);
    if (await f.exists()) {
      await f.delete();
    }
  }

  File _fileForHash(String hash) {
    final aa = hash.substring(0, 2);
    final bb = hash.substring(2, 4);
    final sep = Platform.pathSeparator;

    return File('${_baseDir.path}$sep$aa$sep$bb$sep$hash');
  }
}
