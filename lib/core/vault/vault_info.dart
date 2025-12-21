// lib/core/vault/vault_info.dart
import 'dart:convert';

class VaultInfo {
  static const int schemaVersion = 1;

  final int schemaVersionValue;
  final String vaultId; // UUID string
  final String createdAtUtc; // ISO 8601 UTC string, e.g. 2025-12-18T12:34:56Z

  VaultInfo({
    required this.schemaVersionValue,
    required this.vaultId,
    required this.createdAtUtc,
  });

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersionValue,
      'vaultId': vaultId,
      'createdAtUtc': createdAtUtc,
    };
  }

  String toJsonString({bool pretty = true}) {
    final map = toJson();
    if (!pretty) return jsonEncode(map);
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static VaultInfo fromJson(Map<String, dynamic> json) {
    return VaultInfo(
      schemaVersionValue: json['schemaVersion'] as int,
      vaultId: json['vaultId'] as String,
      createdAtUtc: json['createdAtUtc'] as String,
    );
  }
}
