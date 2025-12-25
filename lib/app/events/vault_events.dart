/* lib/app/events/vault_events.dart */
import 'app_event.dart';

class VaultOpened extends AppEvent {
  final String vaultPath;
  const VaultOpened(this.vaultPath);
}

class VaultClosed extends AppEvent {
  final String? previousVaultPath;
  const VaultClosed(this.previousVaultPath);
}

class VaultOpenFailed extends AppEvent {
  final String vaultPath;
  final String message;
  const VaultOpenFailed(this.vaultPath, this.message);
}
