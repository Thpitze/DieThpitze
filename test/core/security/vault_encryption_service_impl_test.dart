import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/security/vault_crypto_models.dart';
import 'package:thpitze_main/core/security/vault_encryption_service_impl.dart';
import 'package:thpitze_main/core/security/vault_payload_codec.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';

Uint8List b64(String s) => base64Decode(s);

void main() {
  test('deriveKey + encrypt/decrypt roundtrip', () async {
    final svc = VaultEncryptionServiceImpl();

    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
    final infoBase = VaultEncryptionInfo.enabledV1(
      saltB64: base64Encode(salt),
      kdfParams: const VaultKdfParamsV1(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
      ),
      keyCheckB64: 'AA==', // placeholder, not used here
    );

    final key = await svc.deriveKey(info: infoBase, password: 'pw', salt: salt);

    final plain = Uint8List.fromList(
      List<int>.generate(64, (i) => (i * 3) & 0xFF),
    );

    final payload = await svc.encrypt(
      info: infoBase,
      key: key,
      plaintext: plain,
    );

    final dec = await svc.decrypt(info: infoBase, key: key, payload: payload);

    expect(dec, plain);
    expect(payload.nonce.length, VaultPayloadCodec.nonceLen);
    expect(payload.tag.length, VaultPayloadCodec.tagLen);

    // Ensure codec roundtrip works with the new framing
    final encoded = VaultPayloadCodec.encodeB64(payload);
    final decoded = VaultPayloadCodec.decodeB64(encoded);
    expect(decoded.nonce, payload.nonce);
    expect(decoded.tag, payload.tag);
    expect(decoded.ciphertext, payload.ciphertext);
  });

  test('wrong password => Locked via keyCheck', () async {
    final svc = VaultEncryptionServiceImpl();

    final salt = Uint8List.fromList(List<int>.generate(16, (i) => 0xA0 + i));
    final infoNoCheck = VaultEncryptionInfo.enabledV1(
      saltB64: base64Encode(salt),
      kdfParams: const VaultKdfParamsV1(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
      ),
      keyCheckB64: 'AA==', // temp
    );

    final keyGood = await svc.deriveKey(
      info: infoNoCheck,
      password: 'correct',
      salt: salt,
    );

    final keyCheckB64 = await svc.buildKeyCheckB64(
      info: infoNoCheck,
      key: keyGood,
    );

    final info = VaultEncryptionInfo.enabledV1(
      saltB64: base64Encode(salt),
      kdfParams: const VaultKdfParamsV1(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
      ),
      keyCheckB64: keyCheckB64,
    );

    final keyBad = await svc.deriveKey(
      info: info,
      password: 'wrong',
      salt: salt,
    );

    await expectLater(
      () => svc.verifyKeyCheckB64(info: info, key: keyBad),
      throwsA(isA<VaultCryptoLocked>()),
    );

    // Sanity: correct key passes
    await svc.verifyKeyCheckB64(info: info, key: keyGood);
  });

  test('tamper payload => Corrupt', () async {
    final svc = VaultEncryptionServiceImpl();

    final salt = Uint8List.fromList(List<int>.generate(16, (i) => 0x11 + i));
    final info = VaultEncryptionInfo.enabledV1(
      saltB64: base64Encode(salt),
      kdfParams: const VaultKdfParamsV1(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
      ),
      keyCheckB64: 'AA==',
    );

    final key = await svc.deriveKey(info: info, password: 'pw', salt: salt);

    final plain = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]);
    final payload = await svc.encrypt(info: info, key: key, plaintext: plain);

    // Flip one bit in ciphertext
    final tamperedCt = Uint8List.fromList(payload.ciphertext);
    if (tamperedCt.isNotEmpty) {
      tamperedCt[0] ^= 0x01;
    }

    final tampered = EncryptedPayload(
      nonce: payload.nonce,
      ciphertext: tamperedCt,
      tag: payload.tag,
    );

    await expectLater(
      () => svc.decrypt(info: info, key: key, payload: tampered),
      throwsA(isA<VaultCryptoCorrupt>()),
    );
  });
}
