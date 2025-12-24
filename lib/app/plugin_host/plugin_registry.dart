// lib/app/plugin_host/plugin_registry.dart
import '../plugin_api/host_api.dart';
import '../plugin_api/thpitze_plugin.dart';
import 'plugin_capability.dart';

class PluginRegistration {
  final ThpitzePlugin plugin;
  final Set<PluginCapability> grants;

  PluginRegistration({
    required this.plugin,
    required this.grants,
  });
}

class PluginRegistry {
  final Map<String, PluginRegistration> _byId = {};

  List<PluginRegistration> get all =>
      _byId.values.toList(growable: false);

  void register(ThpitzePlugin plugin, {Set<PluginCapability> grants = const {}}) {
    final d = plugin.descriptor;

    if (d.hostApiMajor != hostApiMajor) {
      throw StateError(
        'Plugin "${d.pluginId}" incompatible: plugin hostApiMajor=${d.hostApiMajor} '
        'but host=$hostApiMajor',
      );
    }

    if (_byId.containsKey(d.pluginId)) {
      throw StateError('Duplicate pluginId: "${d.pluginId}"');
    }

    plugin.onRegister();
    _byId[d.pluginId] = PluginRegistration(plugin: plugin, grants: grants);
  }
}
