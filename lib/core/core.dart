// lib/core/core.dart

// Public API for the Core layer.
// UI / Plugins should import ONLY this file.

export 'core_bootstrap.dart';
export 'core_context.dart';

export 'time/clock.dart';

export 'vault/vault_identity_service.dart';
export 'vault/vault_info.dart';
export 'vault/vault_errors.dart';
export 'vault/vault_profile.dart';

export 'vault/vault_encryption_info.dart';
export 'vault/vault_encryption_metadata_service.dart';

export 'security/vault_crypto_models.dart';
export 'security/vault_encryption_service.dart';

export 'security/vault_payload_codec.dart';
export 'security/vault_encryption_service_impl.dart';
export 'records/record.dart';
export 'records/record_codec.dart';
export 'records/record_service.dart';
export 'records/record_header.dart';
