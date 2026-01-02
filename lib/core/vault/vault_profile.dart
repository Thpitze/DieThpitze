/* lib/core/vault/vault_profile.dart */
import 'dart:convert';

import 'package:thpitze_main/core/vault/vault_errors.dart';

/// Vault-scoped profile (portable with the vault).
///
/// File: <vaultRoot>/profile.json
/// Schema: thpitze.vault_profile.v1
class VaultProfile {
  static const String schema = 'thpitze.vault_profile.v1';

  final String schemaValue;
  final VaultProfileSecurity security;
  final VaultProfileUi ui;

  VaultProfile({
    required this.schemaValue,
    required this.security,
    required this.ui,
  });

  factory VaultProfile.defaults() {
    return VaultProfile(
      schemaValue: schema,
      security: VaultProfileSecurity.defaults(),
      ui: VaultProfileUi.defaults(),
    );
  }

  VaultProfile copyWith({VaultProfileSecurity? security, VaultProfileUi? ui}) {
    return VaultProfile(
      schemaValue: schemaValue,
      security: security ?? this.security,
      ui: ui ?? this.ui,
    );
  }

  Map<String, dynamic> toJsonMap() => <String, dynamic>{
    'schema': schemaValue,
    'security': security.toJsonMap(),
    'ui': ui.toJsonMap(),
  };

  String toJsonString({bool pretty = true}) {
    final obj = toJsonMap();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(obj)
        : jsonEncode(obj);
  }

  factory VaultProfile.fromJsonMap(Map<String, dynamic> m) {
    final schemaAny = m['schema'];
    if (schemaAny is! String || schemaAny.isEmpty) {
      throw VaultCorruptException('profile.json missing/invalid "schema"');
    }
    if (schemaAny != schema) {
      throw VersionUnsupportedException(
        'profile.json schema unsupported: "$schemaAny" (expected "$schema")',
      );
    }

    final secAny = m['security'];
    if (secAny is! Map) {
      throw VaultCorruptException('profile.json missing/invalid "security"');
    }

    final uiAny = m['ui'];
    if (uiAny is! Map) {
      throw VaultCorruptException('profile.json missing/invalid "ui"');
    }

    return VaultProfile(
      schemaValue: schemaAny,
      security: VaultProfileSecurity.fromJsonMap(
        Map<String, dynamic>.from(secAny),
      ),
      ui: VaultProfileUi.fromJsonMap(Map<String, dynamic>.from(uiAny)),
    );
  }
}

class VaultProfileSecurity {
  /// 0 disables inactivity locking.
  final int timeoutSeconds;

  /// v1: only "hard" is allowed (reserved for future "soft").
  final String lockPolicy;

  VaultProfileSecurity({
    required this.timeoutSeconds,
    required this.lockPolicy,
  });

  factory VaultProfileSecurity.defaults() {
    return VaultProfileSecurity(timeoutSeconds: 60, lockPolicy: 'hard');
  }

  VaultProfileSecurity copyWith({int? timeoutSeconds, String? lockPolicy}) {
    return VaultProfileSecurity(
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      lockPolicy: lockPolicy ?? this.lockPolicy,
    );
  }

  Map<String, dynamic> toJsonMap() => <String, dynamic>{
    'timeoutSeconds': timeoutSeconds,
    'lockPolicy': lockPolicy,
  };

  factory VaultProfileSecurity.fromJsonMap(Map<String, dynamic> m) {
    final tAny = m['timeoutSeconds'];
    if (tAny is! int || tAny < 0) {
      throw VaultCorruptException(
        'profile.json security.timeoutSeconds missing/invalid',
      );
    }

    final lpAny = m['lockPolicy'];
    if (lpAny is! String || lpAny.isEmpty) {
      throw VaultCorruptException(
        'profile.json security.lockPolicy missing/invalid',
      );
    }

    // v1 rule: only "hard" is accepted.
    if (lpAny != 'hard') {
      throw VersionUnsupportedException(
        'profile.json security.lockPolicy unsupported: "$lpAny" (v1 only supports "hard")',
      );
    }

    return VaultProfileSecurity(timeoutSeconds: tAny, lockPolicy: lpAny);
  }
}

class VaultProfileUi {
  /// Optional UX hint (host may ignore).
  final String? defaultPlugin;

  VaultProfileUi({required this.defaultPlugin});

  factory VaultProfileUi.defaults() {
    return VaultProfileUi(defaultPlugin: 'records_lite');
  }

  VaultProfileUi copyWith({String? defaultPlugin}) {
    return VaultProfileUi(defaultPlugin: defaultPlugin ?? this.defaultPlugin);
  }

  Map<String, dynamic> toJsonMap() => <String, dynamic>{
    'defaultPlugin': defaultPlugin,
  };

  factory VaultProfileUi.fromJsonMap(Map<String, dynamic> m) {
    final dpAny = m['defaultPlugin'];
    if (dpAny == null) {
      return VaultProfileUi(defaultPlugin: null);
    }
    if (dpAny is! String) {
      throw VaultCorruptException('profile.json ui.defaultPlugin invalid');
    }
    return VaultProfileUi(defaultPlugin: dpAny);
  }
}
