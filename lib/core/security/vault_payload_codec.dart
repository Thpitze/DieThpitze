// lib/core/security/vault_payload_codec.dart
//
// P19.2: Encode/decode EncryptedPayload to a compact Base64 representation.
//
// Format: [nonce(12)] [tag(16)] [ciphertext(N)]
// Total length >= 28 bytes.

import 'dart:convert';
import 'dart:typed_data';

import 'package:thpitze_main/core/security/vault_crypto_models.dart';

class VaultPayloadCodec {
  static const int nonceLen = 12;
  static const int tagLen = 16;
  static const int minLen = nonceLen + tagLen;

  static String encodeB64(EncryptedPayload p) {
    final out = Uint8List(minLen + p.ciphertext.length);
    out.setAll(0, p.nonce);
    out.setAll(nonceLen, p.tag);
    out.setAll(minLen, p.ciphertext);
    return base64Encode(out);
  }

  static EncryptedPayload decodeB64(String b64) {
    final bytes = base64Decode(b64);
    if (bytes.length < minLen) {
      throw const FormatException('Encrypted payload too short');
    }

    final nonce = Uint8List.fromList(bytes.sublist(0, nonceLen));
    final tag = Uint8List.fromList(bytes.sublist(nonceLen, minLen));
    final ct = Uint8List.fromList(bytes.sublist(minLen));

    return EncryptedPayload(nonce: nonce, ciphertext: ct, tag: tag);
  }
}
