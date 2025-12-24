// lib/app/plugin_api/plugin_descriptor.dart

class PluginDescriptor {
  final String pluginId;
  final String displayName;
  final int hostApiMajor;

  const PluginDescriptor({
    required this.pluginId,
    required this.displayName,
    required this.hostApiMajor,
  });
}
