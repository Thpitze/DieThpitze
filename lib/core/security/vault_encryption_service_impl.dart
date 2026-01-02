// lib/core/security/vault_encryption_service_impl.dart
//
// P19.2: Real encryption implementation (Argon2id + AES-256-GCM).
//
// Locked vs Error model:
// - Use verifyKeyCheckB64() immediately after deriving key:
//     failure => VaultCryptoLocked
// - After key is verified, record decrypt/auth failures => VaultCryptoCorrupt

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';
import 'package:cryptography/cryptography.dart';

import 'package:thpitze_main/core/security/vault_crypto_models.dart';
import 'package:thpitze_main/core/security/vault_encryption_service.dart';
import 'package:thpitze_main/core/security/vault_payload_codec.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';

class VaultEncryptionServiceImpl implements VaultEncryptionService {
  static const int _keyLen = 32;
  static const int _nonceLen = VaultPayloadCodec.nonceLen;

  static final Uint8List _keyCheckPlain = Uint8List.fromList(
    utf8.encode('THPITZE_KEYCHECK_V1'),
  );

  final Cipher _aead;

  VaultEncryptionServiceImpl({Cipher? aead})
    : _aead = aead ?? AesGcm.with256bits();

  @override
  Future<VaultKey> deriveKey({
    required VaultEncryptionInfo info,
    required String password,
    required Uint8List salt,
  }) async {
    _requireEnabledV1(info);

    final kp = info.kdfParams!;
    final params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      iterations: kp.iterations,
      memory: kp.memoryKiB, // 1KiB blocks in this argon2 implementation
      lanes: kp.parallelism,
      version: Argon2Parameters.ARGON2_VERSION_13,
      converter: CharToByteConverter.UTF8,
    );

    final gen = Argon2BytesGenerator();
    gen.init(params);

    final out = Uint8List(_keyLen);
    gen.generateBytesFromString(password, out, 0, _keyLen);

    return VaultKey(out);
  }

  @override
  Future<EncryptedPayload> encrypt({
    required VaultEncryptionInfo info,
    required VaultKey key,
    required Uint8List plaintext,
    Uint8List? aad,
  }) async {
    _requireEnabledV1(info);

    final secretKey = SecretKeyData(key.bytes);
    final nonce = _randomBytes(_nonceLen);

    final box = await _aead.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad ?? const <int>[],
    );

    return EncryptedPayload(
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      tag: Uint8List.fromList(box.mac.bytes),
    );
  }

  @override
  Future<Uint8List> decrypt({
    required VaultEncryptionInfo info,
    required VaultKey key,
    required EncryptedPayload payload,
    Uint8List? aad,
  }) async {
    _requireEnabledV1(info);

    final secretKey = SecretKeyData(key.bytes);
    final box = SecretBox(
      payload.ciphertext,
      nonce: payload.nonce,
      mac: Mac(payload.tag),
    );

    try {
      final plain = await _aead.decrypt(
        box,
        secretKey: secretKey,
        aad: aad ?? const <int>[],
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoCorrupt('AEAD authentication failed');
    } catch (e) {
      throw VaultCryptoCorrupt('Decrypt failed: $e');
    }
  }

  /// Build keyCheckB64 for a newly created encrypted vault.
  Future<String> buildKeyCheckB64({
    required VaultEncryptionInfo info,
    required VaultKey key,
  }) async {
    final p = await encrypt(info: info, key: key, plaintext: _keyCheckPlain);
    return VaultPayloadCodec.encodeB64(p);
  }

  /// Verify keyCheckB64. Any failure => Locked.
  Future<void> verifyKeyCheckB64({
    required VaultEncryptionInfo info,
    required VaultKey key,
  }) async {
    _requireEnabledV1(info);

    final b64 = (info.keyCheckB64 ?? '').trim();
    if (b64.isEmpty) {
      throw const VaultCryptoUnsupported(
        'Missing keyCheckB64 in encryption metadata',
      );
    }

    final payload = VaultPayloadCodec.decodeB64(b64);
    try {
      final plain = await decrypt(info: info, key: key, payload: payload);
      if (!_constantTimeEq(plain, _keyCheckPlain)) {
        throw const VaultCryptoLocked();
      }
    } on VaultCryptoCorrupt {
      throw const VaultCryptoLocked();
    }
  }

  void _requireEnabledV1(VaultEncryptionInfo info) {
    if (!info.isEnabled || info.version != 1) {
      throw const VaultCryptoUnsupported(
        'Vault encryption is not enabled (v1 required)',
      );
    }
    if ((info.saltB64 ?? '').trim().isEmpty) {
      throw const VaultCryptoUnsupported(
        'Missing saltB64 in encryption metadata',
      );
    }
    if (info.kdfParams == null) {
      throw const VaultCryptoUnsupported(
        'Missing kdfParams in encryption metadata',
      );
    }
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = r.nextInt(256);
    }
    return b;
  }

  static bool _constantTimeEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
  }
}
