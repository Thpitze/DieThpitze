/* lib/app/vault/change_vault_security_dialog.dart */
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/vault/vault_auth_service.dart';
import 'vault_controller.dart';
import 'vault_state.dart';

class ChangeVaultSecurityDialog extends StatefulWidget {
  final VaultController vault;

  const ChangeVaultSecurityDialog({super.key, required this.vault});

  @override
  State<ChangeVaultSecurityDialog> createState() => _ChangeVaultSecurityDialogState();
}

class _ChangeVaultSecurityDialogState extends State<ChangeVaultSecurityDialog> {
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
    final f = File('$path${Platform.pathSeparator}$_authFileName');
    return f.existsSync();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Reads vaultId from <vaultRoot>/vault.json.
  /// We do this locally to avoid depending on a specific VaultIdentityService API shape.
  String _readVaultId(Directory vaultRoot) {
    final f = File('${vaultRoot.path}${Platform.pathSeparator}$_vaultFileName');
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

      // Minimal vault info required by VaultAuthService: vaultId.
            final vaultId = _readVaultId(root);

      const authSvc = VaultAuthService();
      authSvc.enablePasswordProtection(
        vaultRoot: root,
        vaultId: vaultId,
        password: p1,
      );if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Password protection enabled.');
    } catch (e) {
      _toast('Enable failed: $e');
      setState(() => _busy = false);
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
      // Verify current password by attempting unlock/open (session not remembered).
      await widget.vault.unlockWithPassword(password: current, rememberForSession: false);

      // If unlock succeeded, remove auth.json
      final root = Directory(path);
      const authSvc = VaultAuthService();
      authSvc.disablePasswordProtection(vaultRoot: root);

      // Safety: lock immediately (forces re-evaluation of access)
      await widget.vault.lockNow(reason: 'security_changed');

      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Password protection disabled.');
    } catch (e) {
      _toast('Disable failed: $e');
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _vaultPath ?? '(no vault)';
    final mounted = widget.vault.state.kind == VaultStateKind.open ||
        widget.vault.state.kind == VaultStateKind.locked;

    final protected = (_vaultPath != null) ? _hasAuthJson(_vaultPath!) : false;

    return AlertDialog(
      title: const Text('Change profile / security'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Vault: $path',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Current mode: ${protected ? 'Password' : 'Open'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            if (!mounted) const Text('No vault mounted.') else ...[
              if (!protected) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Enable password protection'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newPw1Ctrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  enabled: !_busy,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newPw2Ctrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repeat new password'),
                  enabled: !_busy,
                ),
              ] else ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Disable password protection'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _currentPwCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                  enabled: !_busy,
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (mounted && !protected)
          FilledButton(
            onPressed: _busy ? null : _enablePassword,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enable'),
          ),
        if (mounted && protected)
          FilledButton(
            onPressed: _busy ? null : _disablePassword,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Disable'),
          ),
      ],
    );
  }
}

