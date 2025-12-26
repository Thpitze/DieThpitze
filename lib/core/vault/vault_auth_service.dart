// lib/core/vault/vault_auth_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'vault_errors.dart';
import 'vault_info.dart';

enum VaultAuthMode { unauthenticated, passwordProtected }

class VaultAuthConfig {
  final VaultAuthMode mode;
  final Uint8List? salt;
  final Uint8List? mac;
  final int iterations;

  const VaultAuthConfig._({
    required this.mode,
    required this.salt,
    required this.mac,
    required this.iterations,
  });

  const VaultAuthConfig.unauthenticated()
      : this._(mode: VaultAuthMode.unauthenticated, salt: null, mac: null, iterations: 0);

  const VaultAuthConfig.passwordProtected({
    required Uint8List salt,
    required Uint8List mac,
    required int iterations,
  }) : this._(
          mode: VaultAuthMode.passwordProtected,
          salt: salt,
          mac: mac,
          iterations: iterations,
        );

  static const String fileName = 'auth.json';

  static VaultAuthConfig loadOrDefault(Directory vaultRoot) {
    final f = File('${vaultRoot.path}${Platform.pathSeparator}$fileName');
    if (!f.existsSync()) return const VaultAuthConfig.unauthenticated();

    final raw = f.readAsStringSync();
    final obj = jsonDecode(raw) as Map<String, dynamic>;

    final mode = (obj['mode'] as String?)?.trim().toLowerCase();
    if (mode == null || mode.isEmpty || mode == 'none' || mode == 'unauthenticated') {
      return const VaultAuthConfig.unauthenticated();
    }

    if (mode != 'password') {
      throw VaultCorruptException('auth.json has unsupported mode: $mode');
    }

    final saltB64 = obj['salt_b64'] as String?;
    final macB64 = obj['mac_b64'] as String?;
    final iters = (obj['iterations'] as num?)?.toInt() ?? 200000;

    if (saltB64 == null || macB64 == null) {
      throw VaultCorruptException('auth.json missing salt_b64 or mac_b64');
    }

    Uint8List decodeB64(String s) => Uint8List.fromList(base64Decode(s));

    final salt = decodeB64(saltB64);
    final mac = decodeB64(macB64);

    if (salt.isEmpty || mac.isEmpty) {
      throw VaultCorruptException('auth.json contains empty salt/mac');
    }

    if (iters < 10000) {
      throw VaultCorruptException('auth.json iterations too low: $iters');
    }

    return VaultAuthConfig.passwordProtected(salt: salt, mac: mac, iterations: iters);
  }
}

class VaultAuthService {
  const VaultAuthService();

  void requireAuth({
    required Directory vaultRoot,
    required VaultInfo vaultInfo,
    required String? password,
  }) {
    final cfg = VaultAuthConfig.loadOrDefault(vaultRoot);

    if (cfg.mode == VaultAuthMode.unauthenticated) return;

    final pw = password?.trim() ?? '';
    if (pw.isEmpty) {
      throw AuthRequiredException('Vault requires authentication.');
    }

    final salt = cfg.salt!;
    final expectedMac = cfg.mac!;
    final iters = cfg.iterations;

    final key = _deriveKey(password: pw, salt: salt, iterations: iters);

    final data = utf8.encode(vaultInfo.vaultId);
    final mac = Hmac(sha256, key).convert(data).bytes;

    if (!_constantTimeEquals(Uint8List.fromList(mac), expectedMac)) {
      throw InvalidCredentialsException('Invalid credentials.');
    }
  }

  Uint8List _deriveKey({
    required String password,
    required Uint8List salt,
    required int iterations,
  }) {
    final pwBytes = Uint8List.fromList(utf8.encode(password));
    final seed = Uint8List(pwBytes.length + salt.length);
    seed.setRange(0, pwBytes.length, pwBytes);
    seed.setRange(pwBytes.length, seed.length, salt);

    var digest = sha256.convert(seed).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return Uint8List.fromList(digest);
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
  }
}
