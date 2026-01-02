// ignore_for_file: use_build_context_synchronously
// lib/app/app_shell.dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'core_adapter_impl.dart';
import 'plugin_host/plugin_host_services.dart';
import 'plugins/ui_plugin.dart';
import 'settings/app_settings.dart';
import 'vault/new_vault_wizard.dart';
import 'vault/vault_controller.dart';
import 'vault/vault_dashboard_controller.dart';
import 'vault/vault_state.dart';
import 'vault/vault_stats_card.dart';
import 'vault/vault_security_dialog.dart';

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

    _vault.addListener(_onChanged);
    _dash.addListener(_onChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _vault.init();
      _maybeAutoPromptAuth();
    });
  }

  @override
  void dispose() {
    _dash.removeListener(_onChanged);
    _dash.disposeController();
    _vault.removeListener(_onChanged);
    _vault.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoPromptAuth();
  }

  void _touch() {
    _vault.recordUserActivity();
  }

  bool _hasAuthJson(String vaultPath) {
    final f = File('$vaultPath${Platform.pathSeparator}auth.json');
    return f.existsSync();
  }

  Future<void> _maybeAutoPromptAuth() async {
    if (_didAutoPromptAuth) return;

    final vs = _vault.state;
    if (vs.kind == VaultStateKind.locked && vs.lockReason == 'auth_required') {
      _didAutoPromptAuth = true;
      await _unlockFlow();
    }
  }

  Future<void> _unlockFlow() async {
    _touch();

    final vs = _vault.state;
    if (vs.kind != VaultStateKind.locked) return;

    final path = vs.vaultPath;
    if (path == null || path.trim().isEmpty) return;

    // If there is no auth.json, do NOT prompt. Just unlock.
    if (!_hasAuthJson(path)) {
      await _vault.unlockWithPassword(password: '');
      return;
    }

    final password = await showDialog<String?>(
      context: context,
      builder: (_) => const _UnlockDialog(),
    );

    if (!mounted) return;
    if (password == null || password.trim().isEmpty) return;

    await _vault.unlockWithPassword(password: password);

    if (!mounted) return;

    if (_vault.state.kind == VaultStateKind.error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unlock failed')));
    }
  }

  Future<void> _pickAndMount() async {
    _touch();
    final messenger = ScaffoldMessenger.of(context);

    final path = await getDirectoryPath();
    if (!mounted) return;
    if (path == null) return;

    await _vault.mount(path);
    if (!mounted) return;

    if (_vault.state.kind == VaultStateKind.locked &&
        _vault.state.lockReason == 'auth_required') {
      await _unlockFlow();
      return;
    }

    if (_vault.state.kind == VaultStateKind.error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to open vault')),
      );
    }
  }

  void _showVaultOptions() {
    _touch();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _VaultOptionsSheet(vault: _vault, onUnlock: () => _unlockFlow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VaultState vs = _vault.state;
    final bool canUseVault = (vs.kind == VaultStateKind.open);

    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) {
        if (event.runtimeType.toString() == 'KeyDownEvent') {
          _touch();
        }
        return KeyEventResult.ignored;
      },
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
                onPressed: _unlockFlow,
                icon: const Icon(Icons.lock_open),
              ),
            if (vs.kind == VaultStateKind.open)
              IconButton(
                tooltip: 'Lock',
                onPressed: () async {
                  _touch();
                  await _vault.lockNow(reason: 'manual');
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Vault locked')));
                },
                icon: const Icon(Icons.lock),
              ),
            if (vs.kind == VaultStateKind.open)
              IconButton(
                tooltip: 'Close vault',
                onPressed: () async {
                  _touch();
                  await _vault.closeVault();
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        body: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vault',
                      style: Theme.of(context).textTheme.titleLarge,
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
                    const SizedBox(height: 16),
                    Text(
                      'Plugins',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.plugins.length,
                        itemBuilder: (context, index) {
                          final plugin = widget.plugins[index];
                          return Card(
                            child: ListTile(
                              title: Text(plugin.displayName),
                              subtitle: Text(plugin.pluginId),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: canUseVault
                                  ? () {
                                      _touch();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => plugin.buildScreen(
                                            adapter: _adapter,
                                            eventBus:
                                                widget.hostServices.eventBus,
                                            workingMemory: widget
                                                .hostServices
                                                .workingMemory,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                    if (!canUseVault)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Open a vault to use plugins.'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultOptionsSheet extends StatefulWidget {
  final VaultController vault;
  final Future<void> Function() onUnlock;

  const _VaultOptionsSheet({required this.vault, required this.onUnlock});

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

  String _joinFs(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }

  Future<void> _mountPath(String p, {bool persistAsLast = false}) async {
    final messenger = ScaffoldMessenger.of(context);

    final path = p.trim();
    if (path.isEmpty) return;

    await widget.vault.mount(path, persistAsLast: persistAsLast);
    if (!mounted) return;

    if (widget.vault.state.kind == VaultStateKind.locked &&
        widget.vault.state.lockReason == 'auth_required') {
      await widget.onUnlock();
      if (!mounted) return;
    }

    if (widget.vault.state.kind == VaultStateKind.error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to open vault')),
      );
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vs = widget.vault.state;

    final recents = widget.vault.recentVaultPaths;

    final String? mountedPath = vs.vaultPath;
    final bool hasMountedVault =
        mountedPath != null &&
        mountedPath.trim().isNotEmpty &&
        vs.kind != VaultStateKind.closed;

    final bool isPasswordProtected = hasMountedVault
        ? File(_joinFs(mountedPath, 'auth.json')).existsSync()
        : false;

    final bool canChangeSecurity =
        vs.kind == VaultStateKind.open || vs.kind == VaultStateKind.locked;

    String vaultStateLabel;
    switch (vs.kind) {
      case VaultStateKind.closed:
        vaultStateLabel = 'Closed';
        break;
      case VaultStateKind.opening:
        vaultStateLabel = 'Opening';
        break;
      case VaultStateKind.open:
        vaultStateLabel = 'Open';
        break;
      case VaultStateKind.locked:
        vaultStateLabel = 'Locked';
        break;
      case VaultStateKind.error:
        vaultStateLabel = 'Error';
        break;
    }

    final String passwordProtectionLabel = hasMountedVault
        ? (isPasswordProtected ? 'Enabled' : 'Disabled')
        : '—';

    final int currentMinutes = (widget.vault.vaultTimeoutSeconds / 60).round();
    final int dropdownValue = _timeoutMinutes.contains(currentMinutes)
        ? currentMinutes
        : 0;
    final String timeoutLabel = dropdownValue == 0
        ? 'Off'
        : '$dropdownValue min';

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
                Text(
                  'Vault options',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final createdPath = await NewVaultWizard.show(context);
                    if (!mounted) return;
                    final p = (createdPath ?? '').trim();
                    if (p.isEmpty) return;

                    setState(() => _pathCtrl.text = p);
                    await widget.vault.mount(p, persistAsLast: true);
                    if (!mounted) return;

                    if (widget.vault.state.kind == VaultStateKind.locked &&
                        widget.vault.state.lockReason == 'auth_required') {
                      await widget.onUnlock();
                      if (!mounted) return;
                    }

                    setState(() {});
                  },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Make new vault…'),
                ),
                OutlinedButton.icon(
                  onPressed: canChangeSecurity
                      ? () async {
                          await VaultSecurityDialog.show(context, widget.vault);
                          if (!mounted) return;
                          setState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.security),
                  label: const Text('Vault security…'),
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
                    Text(
                      'Current vault',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Path: ${hasMountedVault ? mountedPath : "—"}'),
                    Text('State: $vaultStateLabel'),
                    Text('Password protection: $passwordProtectionLabel'),
                    Text('Inactivity timeout: $timeoutLabel (profile.json)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathCtrl,
              decoration: const InputDecoration(labelText: 'Vault folder path'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                ElevatedButton.icon(
                  onPressed: () async => _mountPath(_pathCtrl.text),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Mount'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                const Text('Inactivity timeout'),
                DropdownButton<int>(
                  value: dropdownValue,
                  items: _timeoutMinutes
                      .map(
                        (m) => DropdownMenuItem<int>(
                          value: m,
                          child: Text(m == 0 ? 'Off' : '$m min'),
                        ),
                      )
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
                  onPressed: (vs.kind == VaultStateKind.locked)
                      ? () async => widget.onUnlock()
                      : null,
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
              child: Text(
                'Recent vaults',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        p,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        setState(() => _pathCtrl.text = p);
                        await _mountPath(p);
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

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final TextEditingController _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlock vault'),
      content: TextField(
        controller: _pw,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Unlock')),
      ],
    );
  }

  void _submit() {
    final pw = _pw.text;
    if (pw.isEmpty) return;
    Navigator.of(context).pop(pw);
  }
}