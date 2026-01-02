// lib/core/vault/vault_encryption_info.dart
//
// P19.2: Versioned vault encryption metadata (data-at-rest declaration).
// Vault root file: <vaultRoot>/encryption.json
//
// Absence => unencrypted vault (backward compatible).
//
// When enabled, encryption.json must include:
// - saltB64 (per-vault random salt for KDF)
// - kdf params (Argon2id params)
// - keyCheckB64 (encrypted constant used to validate derived key -> Locked vs Error split)

class VaultKdfParamsV1 {
  final int memoryKiB; // Argon2 memory cost
  final int iterations; // Argon2 time cost
  final int parallelism; // Argon2 lanes

  const VaultKdfParamsV1({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  static VaultKdfParamsV1 fromJson(Map<String, dynamic> json) {
    int readInt(String k) {
      final v = json[k];
      if (v is int) return v;
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    return VaultKdfParamsV1(
      memoryKiB: readInt('memoryKiB'),
      iterations: readInt('iterations'),
      parallelism: readInt('parallelism'),
    );
  }
}

class VaultEncryptionInfo {
  static const String schemaV1 = 'thpitze.vault_encryption.v1';

  /// "none" or "enabled"
  final String state;

  /// Encryption version (required when enabled).
  final int? version;

  /// Informational fields (validated non-empty when enabled).
  final String? cipher; // e.g. "AES-256-GCM"
  final String? kdf; // e.g. "Argon2id"

  /// Per-vault random salt, Base64 (required when enabled).
  final String? saltB64;

  /// KDF parameters (required when enabled).
  final VaultKdfParamsV1? kdfParams;

  /// Encrypted constant payload (Base64) for key validation (required when enabled).
  /// This allows: wrong key -> Locked, corrupt record later -> Error.
  final String? keyCheckB64;

  final String schema;

  const VaultEncryptionInfo._({
    required this.schema,
    required this.state,
    required this.version,
    required this.cipher,
    required this.kdf,
    required this.saltB64,
    required this.kdfParams,
    required this.keyCheckB64,
  });

  const VaultEncryptionInfo.none()
    : schema = schemaV1,
      state = 'none',
      version = null,
      cipher = null,
      kdf = null,
      saltB64 = null,
      kdfParams = null,
      keyCheckB64 = null;

  /// Enabled encryption declaration (v1). Does NOT generate salt/check; caller must supply.
  const VaultEncryptionInfo.enabledV1({
    String cipher = 'AES-256-GCM',
    String kdf = 'Argon2id',
    required String saltB64,
    required VaultKdfParamsV1 kdfParams,
    required String keyCheckB64,
  }) : this._(
         schema: schemaV1,
         state: 'enabled',
         version: 1,
         cipher: cipher,
         kdf: kdf,
         saltB64: saltB64,
         kdfParams: kdfParams,
         keyCheckB64: keyCheckB64,
       );

  bool get isEnabled => state == 'enabled';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema': schema,
    'state': state,
    if (version != null) 'version': version,
    if (cipher != null) 'cipher': cipher,
    if (kdf != null) 'kdf': kdf,
    if (saltB64 != null) 'saltB64': saltB64,
    if (kdfParams != null) 'kdfParams': kdfParams!.toJson(),
    if (keyCheckB64 != null) 'keyCheckB64': keyCheckB64,
  };

  static VaultEncryptionInfo fromJson(Map<String, dynamic> json) {
    final schema = (json['schema'] ?? '').toString().trim();
    final state = (json['state'] ?? '').toString().trim();

    final versionRaw = json['version'];
    final version = versionRaw is int
        ? versionRaw
        : int.tryParse('${versionRaw ?? ''}');

    final cipher = json['cipher']?.toString();
    final kdf = json['kdf']?.toString();
    final saltB64 = json['saltB64']?.toString();
    final keyCheckB64 = json['keyCheckB64']?.toString();

    VaultKdfParamsV1? kdfParams;
    final kp = json['kdfParams'];
    if (kp is Map<String, dynamic>) {
      kdfParams = VaultKdfParamsV1.fromJson(kp);
    }

    return VaultEncryptionInfo._(
      schema: schema,
      state: state,
      version: version,
      cipher: cipher,
      kdf: kdf,
      saltB64: saltB64,
      kdfParams: kdfParams,
      keyCheckB64: keyCheckB64,
    );
  }
}
