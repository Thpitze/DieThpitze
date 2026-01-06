// lib/app/core_adapter_impl.dart
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../core/core_bootstrap.dart';
import '../core/core_context.dart';
import '../core/records/encrypted_record_service.dart';
import '../core/records/record.dart';
import '../core/records/record_codec.dart';
import '../core/records/record_service.dart';
import '../core/security/vault_crypto_context.dart';
import '../core/time/clock.dart';
import '../core/vault/vault_identity_service.dart';
import 'main_window.dart';

class SystemClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class CoreAdapterImpl implements CoreAdapter {
  static const Uuid _uuid = Uuid();

  CoreContext? _ctx;

  final CoreBootstrap _bootstrap;

  // Plaintext records (unencrypted vaults)
  final RecordService _records;

  // Encrypted records (encrypted vaults)
  final EncryptedRecordService _encryptedRecords;

  CoreAdapterImpl._({
    required CoreBootstrap bootstrap,
    required RecordService records,
    required EncryptedRecordService encryptedRecords,
  })  : _bootstrap = bootstrap,
        _records = records,
        _encryptedRecords = encryptedRecords;

  factory CoreAdapterImpl.defaultForApp() {
    final clock = SystemClock();

    final bootstrap = CoreBootstrap(
      vaultIdentityService: VaultIdentityService(),
      clock: clock,
    );

    final records = RecordService(codec: RecordCodec(), clock: clock);
    final encryptedRecords =
        EncryptedRecordService(codec: RecordCodec(), clock: clock);

    return CoreAdapterImpl._(
      bootstrap: bootstrap,
      records: records,
      encryptedRecords: encryptedRecords,
    );
  }

  CoreContext get _requireCtx {
    final ctx = _ctx;
    if (ctx == null) {
      throw StateError('No vault opened. Call openVault() first.');
    }
    return ctx;
  }

  @override
  Future<void> openVault({required String vaultPath, String? password}) async {
    final dir = Directory(vaultPath);
    _ctx = await _bootstrap.openVault(dir, password: password);
  }

  @override
  Future<void> closeVault() async {
    _ctx = null;
  }

  bool _isEncryptedVault(CoreContext ctx) {
    final crypto = ctx.crypto;
    return crypto != null && crypto.isEncrypted;
  }

  VaultCryptoContext _requireCrypto(CoreContext ctx) {
    final crypto = ctx.crypto;
    if (crypto == null) {
      throw StateError('Encrypted vault expected but CoreContext.crypto was null.');
    }
    return crypto;
  }

  @override
  Future<List<RecordListItem>> listRecords() async {
    final ctx = _requireCtx;

    if (_isEncryptedVault(ctx)) {
      final crypto = _requireCrypto(ctx);

      final headers = await _encryptedRecords.listHeaders(
        vaultRoot: ctx.vaultRoot,
        crypto: crypto,
      );

      return headers
          .map(
            (h) => RecordListItem(
              id: h.id,
              type: h.type,
              tags: List<String>.from(h.tags),
              createdAtUtc: h.updatedAtUtc,
              updatedAtUtc: h.updatedAtUtc,
            ),
          )
          .toList(growable: false);
    }

    final headers = _records.listHeaders(vaultRoot: ctx.vaultRoot);
    return headers
        .map(
          (h) => RecordListItem(
            id: h.id,
            type: h.type,
            tags: List<String>.from(h.tags),
            createdAtUtc: h.updatedAtUtc,
            updatedAtUtc: h.updatedAtUtc,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RecordViewModel> readRecord({required String id}) async {
    final ctx = _requireCtx;

    final Record r;
    if (_isEncryptedVault(ctx)) {
      final crypto = _requireCrypto(ctx);
      r = await _encryptedRecords.read(
        vaultRoot: ctx.vaultRoot,
        crypto: crypto,
        id: id,
      );
    } else {
      r = _records.read(vaultRoot: ctx.vaultRoot, id: id);
    }

    return RecordViewModel(
      id: r.id,
      type: r.type,
      tags: List<String>.from(r.tags),
      createdAtUtc: r.createdAtUtc,
      updatedAtUtc: r.updatedAtUtc,
      bodyMarkdown: r.bodyMarkdown,
    );
  }

  // --- NEW: used by RecordsLite plugin ---

  Future<RecordViewModel> createNote({
    String bodyMarkdown = 'New entry',
  }) async {
    final ctx = _requireCtx;

    if (_isEncryptedVault(ctx)) {
      final crypto = _requireCrypto(ctx);

      // Generate record fully in-memory; NEVER touch disk in plaintext.
      final now = DateTime.now().toUtc().toIso8601String();
      final id = _uuid.v4();

      final record = Record(
        id: id,
        createdAtUtc: now,
        updatedAtUtc: now,
        type: 'note',
        tags: const [],
        bodyMarkdown: bodyMarkdown,
      );

      final Record r = await _encryptedRecords.create(
        vaultRoot: ctx.vaultRoot,
        crypto: crypto,
        record: record,
      );

      return RecordViewModel(
        id: r.id,
        type: r.type,
        tags: List<String>.from(r.tags),
        createdAtUtc: r.createdAtUtc,
        updatedAtUtc: r.updatedAtUtc,
        bodyMarkdown: r.bodyMarkdown,
      );
    }

    final Record r = _records.create(
      vaultRoot: ctx.vaultRoot,
      type: 'note',
      tags: const [],
      bodyMarkdown: bodyMarkdown,
    );

    return RecordViewModel(
      id: r.id,
      type: r.type,
      tags: List<String>.from(r.tags),
      createdAtUtc: r.createdAtUtc,
      updatedAtUtc: r.updatedAtUtc,
      bodyMarkdown: r.bodyMarkdown,
    );
  }

  Future<void> deleteById(String id) async {
    final ctx = _requireCtx;

    if (_isEncryptedVault(ctx)) {
      _encryptedRecords.deleteRecord(vaultRoot: ctx.vaultRoot, recordId: id);
      return;
    }

    _records.deleteRecord(vaultRoot: ctx.vaultRoot, recordId: id);
  }
}
