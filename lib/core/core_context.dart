// lib/core/core_context.dart
import 'dart:io';

import 'package:thpitze_main/core/time/clock.dart';
import 'package:thpitze_main/core/vault/vault_info.dart';

class CoreContext {
  final Directory vaultRoot;
  final VaultInfo vaultInfo;
  final Clock clock;

  CoreContext({
    required this.vaultRoot,
    required this.vaultInfo,
    required this.clock,
  });
}
