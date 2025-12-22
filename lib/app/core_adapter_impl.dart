// lib/app/core_adapter_impl.dart
//
// Concrete CoreAdapter implementation that binds the base GUI (MainWindow)
// to Core (CoreBootstrap + RecordService + VaultIdentityService).
//
// Scope: READ-ONLY UI wiring.
// - open vault (validate)
// - list record headers
// - read record by id
//
// No UI-side domain logic, no file layout knowledge beyond calling Core services.

import 'dart:io';

import 'package:thpitze_main/app/main_window.dart';
import 'package:thpitze_main/core/core_bootstrap.dart';
import 'package:thpitze_main/core/core_context.dart';
import 'package:thpitze_main/core/records/record_codec.dart';
import 'package:thpitze_main/core/records/record_service.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_identity_service.dart';

/// Minimal system clock for UI runtime.
/// (Tests can inject a fixed clock elsewhere; UI uses wall-clock time.)
class SystemClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Concrete adapter used by the base GUI.
class CoreAdapterImpl implements CoreAdapter {
  CoreContext? _ctx;

  final CoreBootstrap _bootstrap;
  final RecordService _records;

  CoreAdapterImpl._({
    required CoreBootstrap bootstrap,
    required RecordService records,
  })  : _bootstrap = bootstrap,
        _records = records;

  /// Default factory for the app: constructs dependencies with production defaults.
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

    // CoreBootstrap validates vault identity + schema and returns a CoreContext.
    // Keep it sync internally; expose async to UI.
    _ctx = _bootstrap.openVault(dir);
  }

  @override
  Future<List<RecordListItem>> listRecords() async {
    final ctx = _requireCtx;

    final headers = _records.listHeaders(vaultRoot: ctx.vaultRoot);

    // RecordHeader currently does not contain createdAtUtc.
    // UI list doesn’t actually need createdAt; we keep the field but set it to ''.
    return headers
        .map(
          (h) => RecordListItem(
            id: h.id,
            type: h.type,
            tags: List<String>.from(h.tags),
            createdAtUtc: '',
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

  @override
  Future<void> closeVault() async {
    _ctx = null;
  }
}
