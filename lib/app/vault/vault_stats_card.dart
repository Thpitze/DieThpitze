/* lib/app/vault/vault_stats_card.dart */
import 'package:flutter/material.dart';

import 'vault_dashboard_controller.dart';

class VaultStatsCard extends StatelessWidget {
  final VaultDashboardSnapshot snap;
  final VoidCallback? onRefresh;

  const VaultStatsCard({
    super.key,
    required this.snap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (snap.isLocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vault stats', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _kv('Vault state', 'LOCKED'),
            _kv('Vault path', snap.vaultPath ?? '—'),
            const SizedBox(height: 8),
            const Text('Vault is locked. Unlock to refresh stats.'),
          ],
        ),
      );
    }

    if (!snap.hasVaultOpen) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('No vault mounted.'),
      );
    }

    final last = snap.lastRefreshUtc;
    final lastStr = last == null ? '—' : last.toLocal().toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Vault stats',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh, // null disables button automatically
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Vault path', snap.vaultPath ?? '—'),
          _kv('Records', snap.recordCount?.toString() ?? '—'),
          _kv('Last refresh', lastStr),
          if (snap.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last error: ${snap.lastError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
