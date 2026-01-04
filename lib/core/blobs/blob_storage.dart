// lib/core/blobs/blob_storage.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../io/atomic_file_writer.dart';
import '../security/vault_crypto_context.dart';
import '../security/vault_payload_codec.dart';
import 'blob_ref.dart';

/// Content-addressed blob storage inside a vault folder.
///
/// Layout: `<vaultRoot>/blobs/sha256/aa/bb/<fullhash>`
///
/// When [crypto] is provided and the vault is encrypted:
/// - If locked: read/write throws VaultCryptoLocked.
/// - If unlocked: bytes are transparently encrypted on disk and decrypted on read.
///
/// Note: SHA256 is always computed on plaintext bytes to preserve content-addressing
/// across encrypted/unencrypted implementations.
class BlobStorage {
  final Directory vaultRoot;
  final VaultCryptoContext? crypto;

  BlobStorage({required this.vaultRoot, this.crypto});

  Directory get _baseDir => Directory(
        '${vaultRoot.path}${Platform.pathSeparator}blobs'
        '${Platform.pathSeparator}sha256',
      );

  Future<BlobRef> putBytes(Uint8List bytes, {String? mimeType}) async {
    final digest = sha256.convert(bytes);
    final hash = digest.toString(); // lowercase hex
    final size = bytes.length;

    final file = _fileForHash(hash);

    final Uint8List dataToWrite;
    final ctx = crypto;

    if (ctx != null && ctx.isEncrypted) {
      if (ctx.isLocked) {
        // Correct semantics: encrypted vault must not allow plaintext storage while locked.
        throw const VaultCryptoLocked('Vault is locked; cannot write encrypted blob.');
      }

      final payload = await ctx.requireEncryptionService.encrypt(
        info: ctx.requireInfo,
        key: ctx.requireKey,
        plaintext: bytes,
      );

      final b64 = VaultPayloadCodec.encodeB64(payload);
      dataToWrite = Uint8List.fromList(utf8.encode(b64));
    } else {
      // Unencrypted vault: write raw bytes.
      dataToWrite = bytes;
    }

    // Atomic write-if-absent (race-safe)
    await AtomicFileWriter.writeBytesIfAbsent(file, dataToWrite);

    return BlobRef(sha256: hash, sizeBytes: size, mimeType: mimeType);
  }

  Future<bool> exists(String sha256Hex) async {
    return _fileForHash(sha256Hex).exists();
  }

  /// Stream bytes. For encrypted vaults, this yields DECRYPTED bytes (buffered).
  Stream<List<int>> openRead(String sha256Hex) async* {
    final file = _fileForHash(sha256Hex);
    final ctx = crypto;

    if (ctx != null && ctx.isEncrypted) {
      if (ctx.isLocked) {
        throw const VaultCryptoLocked('Vault is locked; cannot read encrypted blob.');
      }

      final raw = await file.readAsBytes();
      final b64 = utf8.decode(raw);
      final payload = VaultPayloadCodec.decodeB64(b64);

      final plain = await ctx.requireEncryptionService.decrypt(
        info: ctx.requireInfo,
        key: ctx.requireKey,
        payload: payload,
      );

      yield plain;
      return;
    }

    // Unencrypted: stream directly.
    yield* file.openRead();
  }

  Future<Uint8List> readBytes(String sha256Hex) async {
    final file = _fileForHash(sha256Hex);
    final raw = await file.readAsBytes();
    final ctx = crypto;

    if (ctx != null && ctx.isEncrypted) {
      if (ctx.isLocked) {
        throw const VaultCryptoLocked('Vault is locked; cannot read encrypted blob.');
      }

      final b64 = utf8.decode(raw);
      final payload = VaultPayloadCodec.decodeB64(b64);

      final plain = await ctx.requireEncryptionService.decrypt(
        info: ctx.requireInfo,
        key: ctx.requireKey,
        payload: payload,
      );

      return plain;
    }

    return Uint8List.fromList(raw);
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

/// Error thrown when a caller tries to access encrypted data without unlocking.
class VaultCryptoLocked implements Exception {
  final String message;
  const VaultCryptoLocked(this.message);
  @override
  String toString() => 'VaultCryptoLocked: $message';
}
