// lib/app/main_window.dart
//
// Base GUI host shell (read-only, Core-adapter driven).
//
// This file intentionally contains ZERO domain logic and ZERO filesystem logic.
// It only:
//   - collects a vault path from the user
//   - opens a vault via an injected CoreAdapter
//   - lists records via the adapter
//   - shows a read-only record view via the adapter
//
// Next step (in a separate drop-in file) will be: implement a CoreAdapter that
// wires into lib/core/* (CoreContext + RecordService + VaultIdentityService).
//
// IMPORTANT: This file compiles without Core, by design. The Core binding is an adapter.

import 'package:flutter/material.dart';

/// UI-facing adapter boundary.
///
/// Implement this in app-layer code that *talks to Core*.
/// The UI must not touch filesystem layout, vault.json, codec, etc.
abstract class CoreAdapter {
  /// Validate and open the vault rooted at [vaultPath].
  /// Should throw a domain error (or any Exception) on failure.
  Future<void> openVault({required String vaultPath, String? password});

  /// List records (typically active records in records/).
  Future<List<RecordListItem>> listRecords();

  /// Load a record by exact id.
  Future<RecordViewModel> readRecord({required String id});

  /// Close current vault (optional; can be a no-op).
  Future<void> closeVault() async {}
}

/// Minimal UI list item (header-level info).
class RecordListItem {
  final String id;
  final String type;
  final List<String> tags;
  final String createdAtUtc;
  final String updatedAtUtc;

  const RecordListItem({
    required this.id,
    required this.type,
    required this.tags,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });
}

/// Minimal UI record view model (header + body).
class RecordViewModel {
  final String id;
  final String type;
  final List<String> tags;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String bodyMarkdown;

  const RecordViewModel({
    required this.id,
    required this.type,
    required this.tags,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.bodyMarkdown,
  });
}

/// Base host window: vault open -> record list -> record view.
///
/// This is the foundation for later plugins. For now, it stays read-only.
class MainWindow extends StatefulWidget {
  final CoreAdapter adapter;

  const MainWindow({super.key, required this.adapter});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

enum _Route { openVault, recordList, recordView }

class _MainWindowState extends State<MainWindow> {
  _Route _route = _Route.openVault;

  // UI state
  String? _openedVaultPath;
  List<RecordListItem> _records = const [];
  RecordViewModel? _currentRecord;

  // Busy/error state
  bool _busy = false;
  String? _error;

  // Vault path input controller (kept alive for UX)
  final TextEditingController _vaultPathCtrl = TextEditingController();

  @override
  void dispose() {
    _vaultPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _doOpenVault() async {
    final path = _vaultPathCtrl.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Vault path is empty.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.adapter.openVault(vaultPath: path);
      final records = await widget.adapter.listRecords();

      if (!mounted) return;
      setState(() {
        _openedVaultPath = path;
        _records = records;
        _currentRecord = null;
        _route = _Route.recordList;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Open failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _refreshList() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final records = await widget.adapter.listRecords();
      if (!mounted) return;
      setState(() => _records = records);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Refresh failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _openRecord(String id) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final rec = await widget.adapter.readRecord(id: id);
      if (!mounted) return;
      setState(() {
        _currentRecord = rec;
        _route = _Route.recordView;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Read failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _closeVault() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.adapter.closeVault();
      if (!mounted) return;
      setState(() {
        _openedVaultPath = null;
        _records = const [];
        _currentRecord = null;
        _route = _Route.openVault;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Close failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (_route == _Route.recordList) ...[
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _refreshList,
              icon: const Icon(Icons.refresh),
            ),
          ],
          if (_openedVaultPath != null) ...[
            IconButton(
              tooltip: 'Close vault',
              onPressed: _busy ? null : _closeVault,
              icon: const Icon(Icons.logout),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
          if (_busy) const Positioned.fill(child: _BusyOverlay()),
        ],
      ),
    );
  }

  String _title() {
    switch (_route) {
      case _Route.openVault:
        return 'Thpitze — Open Vault';
      case _Route.recordList:
        return 'Thpitze — Records';
      case _Route.recordView:
        return 'Thpitze — Record';
    }
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_error != null) ...[
            _ErrorBox(message: _error!),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: switch (_route) {
              _Route.openVault => _OpenVaultView(
                controller: _vaultPathCtrl,
                onOpen: _busy ? null : _doOpenVault,
              ),
              _Route.recordList => _RecordListView(
                vaultPath: _openedVaultPath ?? '',
                items: _records,
                onOpenRecord: _busy ? null : _openRecord,
                onRefresh: _busy ? null : _refreshList,
              ),
              _Route.recordView => _RecordView(
                record: _currentRecord,
                onBack: _busy
                    ? null
                    : () {
                        setState(() {
                          _currentRecord = null;
                          _route = _Route.recordList;
                        });
                      },
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _OpenVaultView extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onOpen;

  const _OpenVaultView({required this.controller, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Vault path',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: r'C:\path\to\vault',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Read-only UI: opens vault, lists records, shows record body.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordListView extends StatelessWidget {
  final String vaultPath;
  final List<RecordListItem> items;
  final void Function(String id)? onOpenRecord;
  final VoidCallback? onRefresh;

  const _RecordListView({
    required this.vaultPath,
    required this.items,
    required this.onOpenRecord,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vault: $vaultPath', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Records',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: items.isEmpty
                ? const Center(child: Text('No records found.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      final tagText = it.tags.isEmpty ? '' : it.tags.join(', ');
                      return ListTile(
                        dense: true,
                        title: Text(it.id),
                        subtitle: Text(
                          '${it.type} | updated ${it.updatedAtUtc}'
                          '${tagText.isEmpty ? '' : ' | tags: $tagText'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: onOpenRecord == null
                            ? null
                            : () => onOpenRecord!(it.id),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _RecordView extends StatelessWidget {
  final RecordViewModel? record;
  final VoidCallback? onBack;

  const _RecordView({required this.record, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final r = record;
    if (r == null) {
      return const Center(child: Text('No record loaded.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                r.id,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('type: ${r.type}'),
                Text('created: ${r.createdAtUtc}'),
                Text('updated: ${r.updatedAtUtc}'),
                Text('tags: ${r.tags.isEmpty ? '-' : r.tags.join(', ')}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Body (markdown, read-only)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                r.bodyMarkdown,
                style: const TextStyle(fontFamily: 'Consolas'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.08),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
