/* lib/app/vault/new_vault_wizard.dart */
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/records/record_service.dart';
import '../../core/vault/vault_auth_service.dart';
import '../../core/vault/vault_identity_service.dart';
import '../../core/vault/vault_profile.dart';
import '../../core/vault/vault_profile_service.dart';

enum _SecurityMode { open, password }

class NewVaultWizard extends StatefulWidget {
  const NewVaultWizard({super.key});

  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const NewVaultWizard()),
    );
  }

  @override
  State<NewVaultWizard> createState() => _NewVaultWizardState();
}

class _NewVaultWizardState extends State<NewVaultWizard> {
  static const String _vaultFileName = 'vault.json';

  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _pw1Ctrl = TextEditingController();
  final TextEditingController _pw2Ctrl = TextEditingController();

  _SecurityMode _mode = _SecurityMode.open;
  int _timeoutSeconds = 60;
  bool _busy = false;

  @override
  void dispose() {
    _pathCtrl.dispose();
    _pw1Ctrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath();
    if (!mounted) return;
    if (dir == null) return;
    setState(() => _pathCtrl.text = dir);
  }

  String _readVaultId(Directory vaultRoot) {
    final f = File('${vaultRoot.path}${Platform.pathSeparator}$_vaultFileName');
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is! Map) throw Exception('vault.json invalid JSON');
    final vaultId = decoded['vaultId'];
    if (vaultId is! String || vaultId.trim().isEmpty) throw Exception('vault.json missing vaultId');
    return vaultId;
  }

  List<DropdownMenuItem<int>> _timeoutItems() {
    const entries = <int, String>{
      0: 'Off',
      60: '1 min',
      300: '5 min',
      900: '15 min',
      1800: '30 min',
      3600: '60 min',
    };

    return [
      for (final e in entries.entries)
        DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
    ];
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _create() async {
    final rawPath = _pathCtrl.text.trim();
    if (rawPath.isEmpty) {
      _toast('Please choose or enter a target folder.');
      return;
    }

    final root = Directory(rawPath);

    // Must be empty or non-existent
    if (root.existsSync()) {
      final contents = root.listSync(followLinks: false);
      if (contents.isNotEmpty) {
        _toast('Target folder must be empty.');
        return;
      }
    }

    if (_mode == _SecurityMode.password) {
      final p1 = _pw1Ctrl.text;
      final p2 = _pw2Ctrl.text;
      if (p1.trim().isEmpty) {
        _toast('Password must not be empty.');
        return;
      }
      if (p1 != p2) {
        _toast('Passwords do not match.');
        return;
      }
    }

    setState(() => _busy = true);

    try {
      if (!root.existsSync()) {
        root.createSync(recursive: true);
      }

      final vaultJson = File(
        '${root.path}${Platform.pathSeparator}${VaultIdentityService.vaultFileName}',
      );
      if (vaultJson.existsSync()) {
        _toast('vault.json already exists in target folder.');
        setState(() => _busy = false);
        return;
      }

      Directory('${root.path}${Platform.pathSeparator}${RecordService.recordsDirName}')
          .createSync(recursive: true);
      Directory('${root.path}${Platform.pathSeparator}${RecordService.trashDirName}')
          .createSync(recursive: true);

      // Creates vault.json
      final idSvc = VaultIdentityService();
      idSvc.initVault(root);

      // profile.json
      final profileSvc = VaultProfileService();
      final base = VaultProfile.defaults();
      final profile = base.copyWith(
        security: base.security.copyWith(timeoutSeconds: _timeoutSeconds),
      );
      await profileSvc.save(root, profile);

      // auth.json (optional)
      if (_mode == _SecurityMode.password) {
        const authSvc = VaultAuthService();
        authSvc.enablePasswordProtection(
          vaultRoot: root,
          vaultId: _readVaultId(root),
          password: _pw1Ctrl.text,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(root.path);
    } catch (e) {
      _toast('Create failed: $e');
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Make new vault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Target folder (must be empty or non-existent).',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vault folder path',
                    hintText: r'C:\...\MyVault',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose...'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Security mode', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AbsorbPointer(
            absorbing: _busy,
            child: RadioGroup<_SecurityMode>(
              groupValue: _mode,
              onChanged: (_SecurityMode? v) {
                if (v == null) return;
                setState(() => _mode = v);
              },
              child: Column(
                children: const [
                  RadioListTile<_SecurityMode>(
                    value: _SecurityMode.open,
                    title: Text('Open (no password)'),
                  ),
                  RadioListTile<_SecurityMode>(
                    value: _SecurityMode.password,
                    title: Text('Password-protected'),
                  ),
                ],
              ),
            ),
          ),
          if (_mode == _SecurityMode.password) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _pw1Ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pw2Ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat password'),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Inactivity timeout (vault-scoped)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _timeoutSeconds,
            items: _timeoutItems(),
            onChanged: _busy ? null : (v) => setState(() => _timeoutSeconds = v ?? 60),
            decoration: const InputDecoration(labelText: 'Timeout'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_busy ? 'Creating...' : 'Create vault'),
          ),
        ],
      ),
    );
  }
}
