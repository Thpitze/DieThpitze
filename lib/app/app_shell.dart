// ignore_for_file: use_build_context_synchronously
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
import 'vault/vault_state.dart';
import 'vault/vault_stats_card.dart';

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

  final FocusNode _focusNode = FocusNode(debugLabel: 'AppShellFocus');

  bool _didAutoPromptAuth = false;

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
    _dash.addListener(_onChanged);
    _vault.addListener(_onChanged);

    Future<void>(() async {
      await _vault.init();
      if (!mounted) return;
      _maybeAutoPromptForUnlock();
    });
  }

  @override
  void dispose() {
    _dash.removeListener(_onChanged);
    _dash.disposeController();
    _vault.removeListener(_onChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoPromptForUnlock();
  }

  void _touch() => _vault.recordUserActivity();

  Future<void> _maybeAutoPromptForUnlock() async {
    final vs = _vault.state;
    if (vs.kind != VaultStateKind.locked) return;
    if (vs.lockReason != 'auth_required') return;
    if (_didAutoPromptAuth) return;

    _didAutoPromptAuth = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showUnlockDialog();
    });
  }

  Future<void> _showUnlockDialog() async {
    // Capture Navigator before async gap (lint-safe)
    final nav = Navigator.of(context);

    final result = await showDialog<_UnlockResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UnlockDialog(),
    );

    if (!mounted) return;
    if (result == null) return;

    await _vault.unlockWithPassword(
      password: result.password,
      rememberForSession: result.rememberForSession,
    );

    if (!mounted) return;

    // Capture messenger before using after any further awaits (lint-safe)
    final messenger = ScaffoldMessenger.of(context);

    final vs = _vault.state;
    if (vs.kind == VaultStateKind.open) {
      messenger.showSnackBar(const SnackBar(content: Text('Vault unlocked')));
      return;
    }

    if (vs.kind == VaultStateKind.locked && vs.lockReason == 'invalid_credentials') {
      messenger.showSnackBar(const SnackBar(content: Text('Incorrect password')));
      _didAutoPromptAuth = false;
      // Use captured navigator (no context after await)
      nav.popUntil((route) => route.isFirst);
      await _maybeAutoPromptForUnlock();
    }
  }

  Future<void> _pickAndMount() async {
    _touch();

    // Capture messenger BEFORE await (lint-safe)
    final messenger = ScaffoldMessenger.of(context);

    final path = await getDirectoryPath();
    if (!mounted) return;
    if (path == null) return;

    await _vault.mount(path);
    if (!mounted) return;

    if (_vault.state.kind == VaultStateKind.locked && _vault.state.lockReason == 'auth_required') {
      await _showUnlockDialog();
      return;
    }

    if (_vault.state.kind == VaultStateKind.error) {
      messenger.showSnackBar(const SnackBar(content: Text('Failed to open vault')));
    }
  }

  void _showVaultOptions() {
    _touch();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VaultOptionsSheet(
        vault: _vault,
        onUnlock: () => _showUnlockDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppEventBus eventBus = widget.hostServices.eventBus;
    final WorkingMemory workingMemory = widget.hostServices.workingMemory;

    final VaultState vs = _vault.state;
    final bool canUseVault = (vs.kind == VaultStateKind.open);

    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, __) {
        _touch();
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (_) => _touch(),
        onPointerMove: (_) => _touch(),
        onPointerSignal: (_) => _touch(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Thpitze'),
            actions: [
              IconButton(
                tooltip: 'Vault options',
                onPressed: _showVaultOptions,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'Mount vault',
                onPressed: _pickAndMount,
                icon: const Icon(Icons.folder_open),
              ),
              if (vs.kind == VaultStateKind.locked)
                IconButton(
                  tooltip: 'Unlock',
                  onPressed: _showUnlockDialog,
                  icon: const Icon(Icons.lock_open),
                ),
              if (vs.kind == VaultStateKind.open)
                IconButton(
                  tooltip: 'Lock now',
                  onPressed: () async {
                    await _vault.lockNow(reason: 'manual');
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vault locked')),
                    );
                  },
                  icon: const Icon(Icons.lock),
                ),
            ],
          ),
          body: Column(
            children: [
              _VaultBanner(
                state: vs,
                lastVaultPath: _vault.lastVaultPath,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: VaultStatsCard(
                  snap: _dash.snap,
                  onRefresh: canUseVault
                      ? () {
                          _touch();
                          _dash.refreshCounts();
                        }
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.plugins.length,
                  itemBuilder: (context, index) {
                    final plugin = widget.plugins[index];
                    final bool enabled = (vs.kind == VaultStateKind.open);

                    return ListTile(
                      enabled: enabled,
                      title: Text(plugin.displayName),
                      subtitle: Text(plugin.pluginId),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: !enabled
                          ? () {
                              final msg = (vs.kind == VaultStateKind.locked)
                                  ? 'Vault locked. Unlock in Vault options.'
                                  : 'No vault open. Use Vault options to mount one.';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg)),
                              );
                            }
                          : () {
                              _touch();
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
      ),
    );
  }
}

class _VaultBanner extends StatelessWidget {
  final VaultState state;
  final String? lastVaultPath;

  const _VaultBanner({
    required this.state,
    required this.lastVaultPath,
  });

  @override
  Widget build(BuildContext context) {
    final kind = state.kind;

    String text;
    if (kind == VaultStateKind.open) {
      text = 'Open: ${state.vaultPath}';
    } else if (kind == VaultStateKind.opening) {
      text = 'Opening: ${state.vaultPath}';
    } else if (kind == VaultStateKind.locked) {
      text = 'Locked (${state.lockReason ?? 'unknown'}): ${state.vaultPath}';
    } else if (kind == VaultStateKind.error) {
      text = 'Error: ${state.errorMessage}';
    } else {
      text = 'No vault mounted${lastVaultPath != null ? ' (last: $lastVaultPath)' : ''}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(text),
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

class _VaultOptionsSheet extends StatefulWidget {
  final VaultController vault;
  final Future<void> Function() onUnlock;

  const _VaultOptionsSheet({
    required this.vault,
    required this.onUnlock,
  });

  @override
  State<_VaultOptionsSheet> createState() => _VaultOptionsSheetState();
}

class _VaultOptionsSheetState extends State<_VaultOptionsSheet> {
  late final TextEditingController _pathCtrl;

  static const List<int> _timeoutMinutes = <int>[0, 1, 5, 15, 30, 60];

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

    final int currentMinutes = (widget.vault.vaultTimeoutSeconds / 60).round();
    final int dropdownValue = _timeoutMinutes.contains(currentMinutes) ? currentMinutes : 0;

    final recents = widget.vault.recentVaultPaths;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Vault options', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathCtrl,
              decoration: const InputDecoration(labelText: 'Vault folder path'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final dir = await getDirectoryPath();
                    if (!mounted) return;
                    if (dir == null) return;
                    setState(() => _pathCtrl.text = dir);
                  },
                  icon: const Icon(Icons.folder),
                  label: const Text('Choose…'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final p = _pathCtrl.text.trim();
                    if (p.isEmpty) return;

                    await widget.vault.mount(p);
                    if (!mounted) return;
                    setState(() {});

                    if (widget.vault.state.kind == VaultStateKind.locked &&
                        widget.vault.state.lockReason == 'auth_required') {
                      await widget.onUnlock();
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Mount'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Inactivity timeout'),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: dropdownValue,
                  items: _timeoutMinutes
                      .map((m) => DropdownMenuItem<int>(
                            value: m,
                            child: Text(m == 0 ? 'Off' : '$m min'),
                          ))
                      .toList(growable: false),
                  onChanged: (val) async {
                    final v = val ?? 0;
                    await widget.vault.setTimeoutSeconds(v * 60);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: (vs.kind == VaultStateKind.open)
                      ? () async {
                          await widget.vault.lockNow(reason: 'manual');
                          if (!mounted) return;
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Vault locked')),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.lock),
                  label: const Text('Lock now'),
                ),
                OutlinedButton.icon(
                  onPressed: (vs.kind == VaultStateKind.locked) ? () async => widget.onUnlock() : null,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
                OutlinedButton.icon(
                  onPressed: (vs.kind == VaultStateKind.open)
                      ? () async {
                          await widget.vault.closeVault();
                          if (!mounted) return;
                          Navigator.of(context).pop();
                        }
                      : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Close vault'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Recent vaults', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            if (recents.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No recent vaults.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: recents.length,
                  itemBuilder: (context, index) {
                    final p = recents[index];
                    return ListTile(
                      dense: true,
                      title: Text(p),
                      onTap: () async {
                        await widget.vault.mount(p);
                        if (!mounted) return;
                        setState(() {});
                        if (widget.vault.state.kind == VaultStateKind.locked &&
                            widget.vault.state.lockReason == 'auth_required') {
                          await widget.onUnlock();
                        }
                      },
                      trailing: IconButton(
                        tooltip: 'Remove from recents',
                        onPressed: () async {
                          await widget.vault.removeRecent(p);
                          if (!mounted) return;
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnlockResult {
  final String password;
  final bool rememberForSession;
  const _UnlockResult({required this.password, required this.rememberForSession});
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final TextEditingController _pw = TextEditingController();
  bool _remember = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlock vault'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: const Text('Remember for this session'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(
              _UnlockResult(password: _pw.text, rememberForSession: _remember),
            );
          },
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}




