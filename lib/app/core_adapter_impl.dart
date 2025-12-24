// lib/app/core_adapter_impl.dart
import 'dart:io';

import '../core/core_bootstrap.dart';
import '../core/core_context.dart';
import '../core/records/record.dart';
import '../core/records/record_codec.dart';
import '../core/records/record_service.dart';
import '../core/time/clock.dart';
import '../core/vault/vault_identity_service.dart';
import 'main_window.dart';

class SystemClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class CoreAdapterImpl implements CoreAdapter {
  CoreContext? _ctx;

  final CoreBootstrap _bootstrap;
  final RecordService _records;

  CoreAdapterImpl._({
    required CoreBootstrap bootstrap,
    required RecordService records,
  })  : _bootstrap = bootstrap,
        _records = records;

  factory CoreAdapterImpl.defaultForApp() {
    final clock = SystemClock();

    final bootstrap = CoreBootstrap(
      vaultIdentityService: VaultIdentityService(),
      clock: clock,
    );

    final records = RecordService(
      codec: RecordCodec(),
      clock: clock,
    );

    return CoreAdapterImpl._(
      bootstrap: bootstrap,
      records: records,
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
  Future<void> openVault({required String vaultPath}) async {
    final dir = Directory(vaultPath);
    _ctx = _bootstrap.openVault(dir);
  }

  @override
  Future<void> closeVault() async {
    _ctx = null;
  }

  @override
  Future<List<RecordListItem>> listRecords() async {
    final ctx = _requireCtx;
    final headers = _records.listHeaders(vaultRoot: ctx.vaultRoot);

    return headers
        .map(
          (h) => RecordListItem(
            id: h.id,
            type: h.type,
            tags: List<String>.from(h.tags),
            // Your RecordHeader doesn't expose createdAtUtc; use updatedAtUtc as a proxy for now.
            createdAtUtc: h.updatedAtUtc,
            updatedAtUtc: h.updatedAtUtc,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RecordViewModel> readRecord({required String id}) async {
    final ctx = _requireCtx;
    final r = _records.read(vaultRoot: ctx.vaultRoot, id: id);

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

  Future<RecordViewModel> createNote({String bodyMarkdown = 'New entry'}) async {
    final ctx = _requireCtx;

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
    _records.deleteRecord(vaultRoot: ctx.vaultRoot, recordId: id);
  }
}
