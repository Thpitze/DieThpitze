/* lib/app/vault/vault_security_dialog.dart */
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/security/vault_encryption_service_impl.dart';
import '../../core/vault/vault_auth_service.dart';
import '../../core/vault/vault_encryption_info.dart';
import '../../core/vault/vault_encryption_metadata_service.dart';
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

  final TextEditingController _encPwCtrl = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _currentPwCtrl.dispose();
    _newPw1Ctrl.dispose();
    _newPw2Ctrl.dispose();
    _encPwCtrl.dispose();
    super.dispose();
  }

  String? get _vaultPath => widget.vault.state.vaultPath;

  bool _hasAuthJson(String path) {
    final f = File(p.join(path, _authFileName));
    return f.existsSync();
  }

  VaultEncryptionInfo _loadEncInfo(String path) {
    final svc = VaultEncryptionMetadataService();
    return svc.loadOrDefault(vaultRoot: Directory(path));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  bool _isVaultEmptyForEncryption(String rootPath) {
    bool hasAnyFiles(String dirName) {
      final d = Directory(p.join(rootPath, dirName));
      if (!d.existsSync()) return false;
      for (final e in d.listSync(recursive: true, followLinks: false)) {
        if (e is File) return true;
      }
      return false;
    }

    // Minimal: require no record/trash files before enabling encryption.
    if (hasAnyFiles('records')) return false;
    if (hasAnyFiles('trash')) return false;

    return true;
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
      setState(() => _busy = false);
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
      final root = Directory(path);
      final vaultId = _readVaultId(root);

      const authSvc = VaultAuthService();
      authSvc.requireAuth(vaultRoot: root, vaultId: vaultId, password: current);

      authSvc.disablePasswordProtection(vaultRoot: root);

      if (!mounted) return;
      _toast('Password protection disabled.');
      setState(() => _busy = false);
    } catch (e) {
      _toast('Disable failed: $e');
      setState(() => _busy = false);
    }
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }

  Future<void> _enableEncryption() async {
    final path = _vaultPath;
    if (path == null) return;

    final pw = _encPwCtrl.text;
    if (pw.trim().isEmpty) {
      _toast('Enter a password to enable encryption.');
      return;
    }

    setState(() => _busy = true);
    try {
      final root = Directory(path);

      // If password protection is enabled, verify password first.
      final vaultId = _readVaultId(root);
      if (_hasAuthJson(path)) {
        const authSvc = VaultAuthService();
        authSvc.requireAuth(vaultRoot: root, vaultId: vaultId, password: pw);
      }

      // Must be empty (no record migration in minimal implementation).
      if (!_isVaultEmptyForEncryption(path)) {
        _toast('Vault is not empty (records/trash found). Encryption enable requires an empty vault (no migration implemented).');
        setState(() => _busy = false);
        return;
      }

      final metaSvc = VaultEncryptionMetadataService();
      final existing = metaSvc.loadOrDefault(vaultRoot: root);
      if (existing.isEnabled) {
        _toast('Encryption already enabled.');
        setState(() => _busy = false);
        return;
      }

      // Build v1 metadata.
      final salt = _randomBytes(16);
      final kdfParams = VaultKdfParamsV1(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 2,
      );

      // Temporary info to derive key (keyCheck filled after encrypt).
      final tmpInfo = VaultEncryptionInfo.enabledV1(
        saltB64: base64Encode(salt),
        kdfParams: kdfParams,
        keyCheckB64: 'pending',
      );

      final encSvc = VaultEncryptionServiceImpl();
      final key = await encSvc.deriveKey(
        info: tmpInfo,
        password: pw,
        salt: salt,
      );
      final keyCheckB64 = await encSvc.buildKeyCheckB64(info: tmpInfo, key: key);

      final info = VaultEncryptionInfo.enabledV1(
        saltB64: base64Encode(salt),
        kdfParams: kdfParams,
        keyCheckB64: keyCheckB64,
      );

      await metaSvc.save(vaultRoot: root, info: info);

      if (!mounted) return;
      _toast('Encryption enabled. Close and re-open the vault to apply.');
      setState(() => _busy = false);
    } catch (e) {
      _toast('Enable encryption failed: $e');
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _vaultPath ?? '(no vault)';
    final isMounted =
        widget.vault.state.kind == VaultStateKind.open ||
        widget.vault.state.kind == VaultStateKind.locked;

    final protected = (_vaultPath != null) ? _hasAuthJson(_vaultPath!) : false;

    final encInfo = (_vaultPath != null) ? _loadEncInfo(_vaultPath!) : const VaultEncryptionInfo.none();
    final encEnabled = encInfo.isEnabled;

    return AlertDialog(
      title: const Text('Vault security'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Vault: $path', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 12),

            if (!isMounted) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No vault mounted.'),
              ),
            ] else ...[
              // Password protection section
              ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Password protection'),
                subtitle: Text(protected ? 'Enabled' : 'Disabled'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (!protected) ...[
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
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy ? null : _enablePassword,
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Enable'),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _currentPwCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Current password'),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy ? null : _disablePassword,
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Disable'),
                      ),
                    ),
                  ],
                ],
              ),

              // Encryption section
              ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Encryption-at-rest'),
                subtitle: Text(encEnabled ? 'Enabled' : 'Disabled'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (!encEnabled) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Minimal implementation: enable only for empty vaults (no migration).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _encPwCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: protected ? 'Password (verify)' : 'Password (used for key derivation)',
                      ),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy ? null : _enableEncryption,
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Enable encryption'),
                      ),
                    ),
                  ] else ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Disable/migrate not implemented yet.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: null,
                        child: const Text('Disable encryption'),
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