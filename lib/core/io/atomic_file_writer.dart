import 'dart:io';
import 'dart:typed_data';

/// Atomic file write helpers using "temp + rename".
///
/// Notes:
/// - We use `flush: true` to flush file contents.
/// - Directory fsync is not available in pure Dart across platforms; this is
///   still a meaningful safety step and matches your existing semantics.
/// - `rename` is atomic on most filesystems when staying on the same volume.
class AtomicFileWriter {
  /// Writes bytes to [target] atomically.
  /// Overwrites existing file (via rename) if rename succeeds and filesystem allows.
  static Future<void> writeBytesAtomic(File target, Uint8List bytes) async {
    await target.parent.create(recursive: true);

    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsBytes(bytes, flush: true);

    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Best-effort cleanup.
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Writes bytes to [target] only if it doesn't exist.
  ///
  /// Returns:
  /// - true  if we wrote the file (won the race)
  /// - false if it already existed (or another writer raced and won)
  static Future<bool> writeBytesIfAbsent(File target, Uint8List bytes) async {
    if (await target.exists()) return false;

    await target.parent.create(recursive: true);

    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsBytes(bytes, flush: true);

    try {
      await tmp.rename(target.path);
      return true;
    } on FileSystemException {
      // If another writer raced and created it, keep existing and delete temp.
      if (await target.exists()) {
        try {
          if (await tmp.exists()) {
            await tmp.delete();
          }
        } catch (_) {}
        return false;
      }

      // Otherwise this is a real failure.
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Writes string to [target] atomically (UTF-8).
  static Future<void> writeStringAtomic(File target, String text) async {
    await target.parent.create(recursive: true);

    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsString(text, flush: true);

    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }
}
