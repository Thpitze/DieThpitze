import 'package:flutter/material.dart';

import '../../core_adapter_impl.dart';
import '../../events/app_event_bus.dart';
import '../../events/working_memory.dart';
import '../../main_window.dart' show RecordListItem;
import '../ui_plugin.dart';

class RecordsLitePlugin implements UiPlugin {
  const RecordsLitePlugin();

  @override
  String get pluginId => 'records_lite';

  @override
  String get displayName => 'Records (Lite)';

  @override
  Widget buildScreen({
    required CoreAdapterImpl adapter,
    required AppEventBus eventBus,
    required WorkingMemory workingMemory,
  }) {
    return _RecordsLiteScreen(adapter: adapter);
  }
}

class _RecordsLiteScreen extends StatefulWidget {
  final CoreAdapterImpl adapter;

  const _RecordsLiteScreen({required this.adapter});

  @override
  State<_RecordsLiteScreen> createState() => _RecordsLiteScreenState();
}

class _RecordsLiteScreenState extends State<_RecordsLiteScreen> {
  bool _busy = false;
  String? _error;
  List<RecordListItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await widget.adapter.listRecords();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await widget.adapter.createNote(bodyMarkdown: 'New entry');
      await _refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _busy = true);
    try {
      await widget.adapter.deleteById(id);
      await _refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Records (Lite)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Create',
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = _items[i];
                return ListTile(
                  title: Text(it.id),
                  subtitle: Text(it.updatedAtUtc),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    onPressed: _busy ? null : () => _delete(it.id),
                    icon: const Icon(Icons.delete),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
