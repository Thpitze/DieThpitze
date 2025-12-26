// lib/core/core_bootstrap.dart
import 'dart:io';

import 'package:thpitze_main/core/core_context.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_auth_service.dart';
import 'package:thpitze_main/core/vault/vault_identity_service.dart';

class CoreBootstrap {
  final VaultIdentityService vaultIdentityService;
  final VaultAuthService vaultAuthService;
  final Clock clock;

  CoreBootstrap({
    required this.vaultIdentityService,
    required this.clock,
    VaultAuthService? vaultAuthService,
  }) : vaultAuthService = vaultAuthService ?? const VaultAuthService();

  CoreContext openVault(Directory vaultRoot, {String? password}) {
    final info = vaultIdentityService.validateVault(vaultRoot);

    vaultAuthService.requireAuth(vaultRoot: vaultRoot, vaultInfo: info, password: password);

    return CoreContext(
      vaultRoot: vaultRoot,
      vaultInfo: info,
      clock: clock,
    );
  }
}
