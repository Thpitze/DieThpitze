// lib/app/plugin_api/thpitze_plugin.dart
import 'plugin_descriptor.dart';

/// Pure plugin contract: NO Flutter types here.
/// UI exposure will be handled by an app/ui adapter later.
abstract class ThpitzePlugin {
  PluginDescriptor get descriptor;

  /// Called once at app start (or registry build).
  void onRegister();
}
