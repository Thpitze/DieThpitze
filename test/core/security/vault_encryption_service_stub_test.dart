import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/security/vault_crypto_models.dart';
import 'package:thpitze_main/core/security/vault_encryption_service.dart';
import 'package:thpitze_main/core/vault/vault_encryption_info.dart';

void main() {
  test(
    'VaultEncryptionServiceStub throws unsupported for all operations',
    () async {
      const info = VaultEncryptionInfo.enabledV1(
        saltB64: 'AAAAAAAAAAAAAAAAAAAAAA==',
        kdfParams: VaultKdfParamsV1(
          memoryKiB: 65536,
          iterations: 3,
          parallelism: 1,
        ),
        keyCheckB64: 'AQIDBAUGBwgJCgsMDQ4PEA==',
      );

      final svc = VaultEncryptionServiceStub();

      await expectLater(
        () => svc.encrypt(
          info: info,
          key: VaultKey(Uint8List(32)),
          plaintext: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<VaultCryptoUnsupported>()),
      );

      await expectLater(
        () => svc.decrypt(
          info: info,
          key: VaultKey(Uint8List(32)),
          payload: EncryptedPayload(
            nonce: Uint8List(12),
            ciphertext: Uint8List(0),
            tag: Uint8List(16),
          ),
        ),
        throwsA(isA<VaultCryptoUnsupported>()),
      );

      await expectLater(
        () => svc.deriveKey(info: info, password: 'x', salt: Uint8List(16)),
        throwsA(isA<VaultCryptoUnsupported>()),
      );
    },
  );
}
