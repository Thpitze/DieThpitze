import 'package:flutter/material.dart';

import 'core_adapter_impl.dart';
import 'events/app_event_bus.dart';
import 'events/working_memory.dart';
import 'plugins/plugins.dart' as plug;
import 'plugins/ui_plugin.dart' as plug_types;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _adapter = CoreAdapterImpl.defaultForApp();
  final _eventBus = AppEventBus();
  final _workingMemory = WorkingMemory();

  String? _vaultPath;
  String? _error;
  bool _busy = false;

  late final List<plug_types.UiPlugin> _plugins = plug.buildPlugins();

  @override
  void dispose() {
    _eventBus.dispose();
    super.dispose();
  }

  Future<void> _openVault(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _adapter.openVault(vaultPath: path);
      _workingMemory.resetVaultScope();
      setState(() => _vaultPath = path);
    } catch (e) {
      setState(() => _error = 'Open failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeVault() async {
    await _adapter.closeVault();
    _workingMemory.resetVaultScope();
    setState(() => _vaultPath = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_vaultPath == null) {
      return _OpenVaultView(
        busy: _busy,
        error: _error,
        onOpen: _openVault,
      );
    }

    return _PluginMenu(
      vaultPath: _vaultPath!,
      plugins: _plugins,
      onCloseVault: _closeVault,
      adapter: _adapter,
      eventBus: _eventBus,
      workingMemory: _workingMemory,
    );
  }
}

class _OpenVaultView extends StatefulWidget {
  final bool busy;
  final String? error;
  final Future<void> Function(String path) onOpen;

  const _OpenVaultView({
    required this.busy,
    required this.error,
    required this.onOpen,
  });

  @override
  State<_OpenVaultView> createState() => _OpenVaultViewState();
}

class _OpenVaultViewState extends State<_OpenVaultView> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thpitze – Open vault')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vault path:'),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              enabled: !widget.busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: r'C:\path\to\vault',
              ),
              onSubmitted: widget.busy ? null : widget.onOpen,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed:
                      widget.busy ? null : () => widget.onOpen(_ctrl.text),
                  child: const Text('Open'),
                ),
                const SizedBox(width: 12),
                if (widget.busy) const CircularProgressIndicator(),
              ],
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              Text(widget.error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PluginMenu extends StatelessWidget {
  final String vaultPath;
  final List<plug_types.UiPlugin> plugins;
  final VoidCallback onCloseVault;

  final CoreAdapterImpl adapter;
  final AppEventBus eventBus;
  final WorkingMemory workingMemory;

  const _PluginMenu({
    required this.vaultPath,
    required this.plugins,
    required this.onCloseVault,
    required this.adapter,
    required this.eventBus,
    required this.workingMemory,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thpitze'),
        actions: [
          IconButton(
            tooltip: 'Close vault',
            onPressed: onCloseVault,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Vault'),
            subtitle: Text(vaultPath),
          ),
          const Divider(),
          for (final p in plugins)
            ListTile(
              title: Text(p.displayName),
              subtitle: Text(p.pluginId),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => p.buildScreen(
                      adapter: adapter,
                      eventBus: eventBus,
                      workingMemory: workingMemory,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
