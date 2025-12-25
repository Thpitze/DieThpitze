// lib/app/app_shell.dart
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'core_adapter_impl.dart';
import 'events/app_event_bus.dart';
import 'events/working_memory.dart';
import 'plugin_host/plugin_host_services.dart';
import 'plugins/ui_plugin.dart';
import 'settings/app_settings.dart';
import 'vault/vault_controller.dart';
import 'vault/vault_dashboard_controller.dart';
import 'vault/vault_stats_card.dart';
import 'vault/vault_state.dart';

class AppShell extends StatefulWidget {
  final PluginHostServices hostServices;
  final List<UiPlugin> plugins;

  const AppShell({
    super.key,
    required this.hostServices,
    required this.plugins,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final CoreAdapterImpl _adapter;
  late final AppSettingsStore _settingsStore;
  late final VaultController _vault;
  late final VaultDashboardController _dash;
  @override
  void initState() {
    super.initState();

    _adapter = CoreAdapterImpl.defaultForApp();
    _settingsStore = AppSettingsStore.defaultStore();

    _vault = VaultController(
      adapter: _adapter,
      workingMemory: widget.hostServices.workingMemory,
      eventBus: widget.hostServices.eventBus,
      settingsStore: _settingsStore,
    );

    _dash = VaultDashboardController(adapter: _adapter, vault: _vault);
    _dash.addListener(_onVaultChanged);

    _vault.addListener(_onVaultChanged);

    // Start async init (auto-mount last vault).
    Future<void>(() async {
      await _vault.init();
    });
  }

  @override
  void dispose() {
    _dash.removeListener(_onVaultChanged);
    _dash.disposeController();
    _vault.removeListener(_onVaultChanged);
    super.dispose();
  }

  void _onVaultChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppEventBus eventBus = widget.hostServices.eventBus;
    final WorkingMemory workingMemory = widget.hostServices.workingMemory;

    final VaultState vs = _vault.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thpitze'),
        actions: [
          IconButton(
            tooltip: 'Vault options',
            onPressed: () => _showVaultOptions(context),
            icon: const Icon(Icons.lock_outline),
          ),
          if (vs.isOpen)
            IconButton(
              tooltip: 'Close vault',
              onPressed: () async {
                await _vault.close();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vault closed')),
                );
              },
              icon: const Icon(Icons.lock_open),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _VaultStatusBanner(state: vs, lastVaultPath: _vault.lastVaultPath),
            const SizedBox(height: 12),
            VaultStatsCard(
              snap: _dash.snap,
              onRefresh: () {
                _dash.refreshCounts();
              },
            ),
            const SizedBox(height: 12),
const SizedBox(height: 16),
            const Text(
              'Plugins',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.plugins.length,
                itemBuilder: (context, index) {
                  final plugin = widget.plugins[index];

                  final bool enabled = vs.isOpen;
                  return ListTile(
                    enabled: enabled,
                    title: Text(plugin.displayName),
                    subtitle: Text(plugin.pluginId),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: !enabled
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No vault open. Use Vault options to mount one.'),
                              ),
                            );
                          }
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _PluginScreenHost(
                                  title: plugin.displayName,
                                  child: plugin.buildScreen(
                                    adapter: _adapter,
                                    eventBus: eventBus,
                                    workingMemory: workingMemory,
                                  ),
                                ),
                              ),
                            );
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVaultOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VaultOptionsSheet(vault: _vault),
    );
  }
}

class _VaultStatusBanner extends StatelessWidget {
  final VaultState state;
  final String? lastVaultPath;

  const _VaultStatusBanner({
    required this.state,
    required this.lastVaultPath,
  });

  @override
  Widget build(BuildContext context) {
    final String headline;
    final String detail;

    switch (state.kind) {
      case VaultStateKind.closed:
        headline = 'Vault: CLOSED';
        detail = lastVaultPath == null ? 'No last vault remembered.' : 'Last vault: $lastVaultPath';
        break;
      case VaultStateKind.opening:
        headline = 'Vault: OPENING';
        detail = state.vaultPath ?? '';
        break;
      case VaultStateKind.open:
        headline = 'Vault: OPEN';
        detail = state.vaultPath ?? '';
        break;
      case VaultStateKind.error:
        headline = 'Vault: ERROR';
        detail = '${state.vaultPath ?? ''}\n${state.errorMessage ?? ''}';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(detail),
        ],
      ),
    );
  }
}

class _VaultOptionsSheet extends StatefulWidget {
  final VaultController vault;

  const _VaultOptionsSheet({required this.vault});

  @override
  State<_VaultOptionsSheet> createState() => _VaultOptionsSheetState();
}

class _VaultOptionsSheetState extends State<_VaultOptionsSheet> {
  late final TextEditingController _pathCtrl;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(text: widget.vault.lastVaultPath ?? '');
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vs = widget.vault.state;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vault options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          TextField(
            controller: _pathCtrl,
            decoration: const InputDecoration(
              labelText: 'Vault path',
              hintText: r'C:\Users\Simon\Desktop\YourVault',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await getDirectoryPath();
                  if (!context.mounted) return;
                  if (picked == null || picked.trim().isEmpty) return;
                  _pathCtrl.text = picked.trim();
                  setState(() {});
                },
                icon: const Icon(Icons.folder),
                label: const Text('Choose…'),
              ),

              ElevatedButton.icon(
                onPressed: () async {
                  final path = _pathCtrl.text.trim();
                  if (path.isEmpty) return;

                  await widget.vault.mount(path);
                  if (!context.mounted) return;

                  if (widget.vault.state.isOpen) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vault mounted')),
                    );
                  } else if (widget.vault.state.kind == VaultStateKind.error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(widget.vault.state.errorMessage ?? 'Failed to open vault')),
                    );
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Mount vault'),
              ),

              OutlinedButton.icon(
                onPressed: (vs.isOpen)
                    ? () async {
                        await widget.vault.close();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vault closed')),
                        );
                        setState(() {});
                      }
                    : null,
                icon: const Icon(Icons.lock_open),
                label: const Text('Close vault'),
              ),

              OutlinedButton.icon(
                onPressed: () async {
                  await widget.vault.clearLastVault();
                  if (!context.mounted) return;
                  _pathCtrl.text = '';
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Last vault cleared')),
                  );
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear last'),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            'Timeout (seconds): ${widget.vault.vaultTimeoutSeconds} (not enforced yet)',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PluginScreenHost extends StatelessWidget {
  final String title;
  final Widget child;

  const _PluginScreenHost({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}







