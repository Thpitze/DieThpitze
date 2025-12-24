// lib/app/plugin_api/plugin.dart
import 'capabilities.dart';
import 'host_services.dart';

/// Stable identity for compile-time plugins.
/// pluginId must never change once shipped (used for namespacing + persistence).
class PluginDescriptor {
  final String pluginId; // e.g. "de.thpitze.records"
  final String displayName;
  final String version; // semver string, e.g. "0.1.0"
  final int requiredHostApiMajor; // compatibility gate (v1 => 1)

  final Set<PluginCapability> capabilities;

  const PluginDescriptor({
    required this.pluginId,
    required this.displayName,
    required this.version,
    required this.requiredHostApiMajor,
    required this.capabilities,
  });
}

/// Plugins must be compile-time modules that implement this interface.
/// No plugin may import another plugin.
abstract class ThpitzePlugin {
  PluginDescriptor get descriptor;

  /// Called once after the plugin is registered and host services are available.
  /// Keep fast; do not block UI.
  void onRegister(PluginHostServices host) {}
}
