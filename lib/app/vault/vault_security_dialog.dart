/* lib/app/vault/vault_security_dialog.dart */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/vault/vault_auth_service.dart';
import 'vault_controller.dart';
import 'vault_state.dart';

class VaultSecurityDialog extends StatefulWidget {
  final VaultController vault;

  const VaultSecurityDialog({super.key, required this.vault});

  static Future<void> show(BuildContext context, VaultController vault) {
    return showDialog<void>(
      context: context,
      builder: (_) => VaultSecurityDialog(vault: vault),
    );
  }

  @override
  State<VaultSecurityDialog> createState() => _VaultSecurityDialogState();
}

class _VaultSecurityDialogState extends State<VaultSecurityDialog> {
  static const String _authFileName = 'auth.json';
  static const String _vaultFileName = 'vault.json';

  final TextEditingController _currentPwCtrl = TextEditingController();
  final TextEditingController _newPw1Ctrl = TextEditingController();
  final TextEditingController _newPw2Ctrl = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _currentPwCtrl.dispose();
    _newPw1Ctrl.dispose();
    _newPw2Ctrl.dispose();
    super.dispose();
  }

  String? get _vaultPath => widget.vault.state.vaultPath;

  bool _hasAuthJson(String path) {
    final f = File(p.join(path, _authFileName));
    return f.existsSync();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String _readVaultId(Directory vaultRoot) {
    final f = File(p.join(vaultRoot.path, _vaultFileName));
    if (!f.existsSync()) {
      throw Exception('vault.json not found');
    }
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is! Map) {
      throw Exception('vault.json invalid JSON');
    }
    final vaultId = decoded['vaultId'];
    if (vaultId is! String || vaultId.trim().isEmpty) {
      throw Exception('vault.json missing vaultId');
    }
    return vaultId;
  }

  Future<void> _enablePassword() async {
    final path = _vaultPath;
    if (path == null) return;

    final p1 = _newPw1Ctrl.text;
    final p2 = _newPw2Ctrl.text;
    if (p1.trim().isEmpty) {
      _toast('Password must not be empty.');
      return;
    }
    if (p1 != p2) {
      _toast('Passwords do not match.');
      return;
    }

    setState(() => _busy = true);
    try {
      final root = Directory(path);
      final vaultId = _readVaultId(root);

      const authSvc = VaultAuthService();
      authSvc.enablePasswordProtection(
        vaultRoot: root,
        vaultId: vaultId,
        password: p1,
      );

      if (!mounted) return;
      _toast('Password protection enabled.');
    } catch (e) {
      _toast('Enable failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disablePassword() async {
    final path = _vaultPath;
    if (path == null) return;

    final current = _currentPwCtrl.text;
    if (current.trim().isEmpty) {
      _toast('Enter current password to disable protection.');
      return;
    }

    setState(() => _busy = true);
    try {
      final root = Directory(path);
      final vaultId = _readVaultId(root);

      const authSvc = VaultAuthService();
      authSvc.requireAuth(
        vaultRoot: root,
        vaultId: vaultId,
        password: current,
      );

      authSvc.disablePasswordProtection(vaultRoot: root);

      if (!mounted) return;
      _toast('Password protection disabled.');
    } catch (e) {
      _toast('Disable failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _vaultPath ?? '(no vault)';
    final isMounted =
        widget.vault.state.kind == VaultStateKind.open ||
        widget.vault.state.kind == VaultStateKind.locked;

    final protected =
        (_vaultPath != null) ? _hasAuthJson(_vaultPath!) : false;

    return AlertDialog(
      title: const Text('Vault security'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Vault: $path',
                  style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 12),

            if (!isMounted) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No vault mounted.'),
              ),
            ] else ...[
              ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Password protection'),
                subtitle: Text(protected ? 'Enabled' : 'Disabled'),
                childrenPadding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (!protected) ...[
                    TextField(
                      controller: _newPw1Ctrl,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'New password'),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _newPw2Ctrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Repeat new password'),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy ? null : _enablePassword,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Enable'),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _currentPwCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Current password'),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy ? null : _disablePassword,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Disable'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
