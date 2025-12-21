// lib/core/core_bootstrap.dart
import 'dart:io';

import 'package:thpitze_main/core/core_context.dart';
import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_identity_service.dart';

class CoreBootstrap {
  final VaultIdentityService vaultIdentityService;
  final Clock clock;

  CoreBootstrap({
    required this.vaultIdentityService,
    required this.clock,
  });

  CoreContext openVault(Directory vaultRoot) {
    final info = vaultIdentityService.validateVault(vaultRoot);

    return CoreContext(
      vaultRoot: vaultRoot,
      vaultInfo: info,
      clock: clock,
    );
  }
}
