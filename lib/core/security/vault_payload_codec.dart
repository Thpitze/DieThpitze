 // lib/core/security/vault_payload_codec.dart
 //
 // P23: Versioned encrypted payload framing.
 //
 // REQUIRED FORMAT (byte-level):
 //   MAGIC | VERSION | NONCE | CIPHERTEXT | TAG
 //
 // - MAGIC:   4 bytes  (ASCII)  "THPZ"
 // - VERSION: 1 byte   (uint8)  currently 1
 // - NONCE:   12 bytes (AES-GCM nonce)
 // - CT:      N bytes
 // - TAG:     16 bytes (AES-GCM tag / mac)
 //
 // Base64 encodes the full byte payload above.

import 'dart:convert';
import 'dart:typed_data';

import 'package:thpitze_main/core/security/vault_crypto_models.dart';

class VaultPayloadCodec {
  // ---- Format constants ----
  // NOTE: Keep MAGIC as const List<int> because Uint8List.fromList is not const.
  static const List<int> magic = <int>[0x54, 0x48, 0x50, 0x5A]; // 'T''H''P''Z'
  static const int version = 1;

  static const int magicLen = 4;
  static const int versionLen = 1;

  static const int nonceLen = 12;
  static const int tagLen = 16;

  static const int headerLen = magicLen + versionLen + nonceLen;
  static const int minLen = headerLen + tagLen; // ciphertext may be empty, tag always present

  static String encodeB64(EncryptedPayload p, {int payloadVersion = version}) {
    if (p.nonce.length != nonceLen) {
      throw FormatException('Nonce must be $nonceLen bytes (got ${p.nonce.length})');
    }
    if (p.tag.length != tagLen) {
      throw FormatException('Tag must be $tagLen bytes (got ${p.tag.length})');
    }
    if (payloadVersion < 0 || payloadVersion > 255) {
      throw const FormatException('payloadVersion must fit in a byte');
    }

    final out = Uint8List(headerLen + p.ciphertext.length + tagLen);

    // MAGIC
    out.setAll(0, magic);

    // VERSION
    out[magicLen] = payloadVersion & 0xFF;

    // NONCE
    out.setAll(magicLen + versionLen, p.nonce);

    // CIPHERTEXT
    out.setAll(headerLen, p.ciphertext);

    // TAG (last)
    out.setAll(headerLen + p.ciphertext.length, p.tag);

    return base64Encode(out);
  }

  static EncryptedPayload decodeB64(String b64) {
    final bytes = base64Decode(b64);
    if (bytes.length < minLen) {
      throw const FormatException('Encrypted payload too short');
    }

    // MAGIC
    for (var i = 0; i < magicLen; i++) {
      if (bytes[i] != magic[i]) {
        throw const FormatException('Encrypted payload has invalid MAGIC');
      }
    }

    // VERSION
    final v = bytes[magicLen];
    if (v != version) {
      throw FormatException('Unsupported encrypted payload version: $v');
    }

    // NONCE
    final nonceStart = magicLen + versionLen;
    final nonceEnd = nonceStart + nonceLen;
    final nonce = Uint8List.fromList(bytes.sublist(nonceStart, nonceEnd));

    // TAG is last 16 bytes
    final tagStart = bytes.length - tagLen;
    if (tagStart < nonceEnd) {
      throw const FormatException('Encrypted payload framing invalid');
    }

    final ct = Uint8List.fromList(bytes.sublist(nonceEnd, tagStart));
    final tag = Uint8List.fromList(bytes.sublist(tagStart));

    return EncryptedPayload(nonce: nonce, ciphertext: ct, tag: tag);
  }
}
