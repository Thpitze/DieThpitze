// lib/core/blobs/blob_ref.dart

class BlobRef {
  final String sha256; // lowercase hex
  final int sizeBytes;
  final String? mimeType;

  const BlobRef({
    required this.sha256,
    required this.sizeBytes,
    this.mimeType,
  });
}
