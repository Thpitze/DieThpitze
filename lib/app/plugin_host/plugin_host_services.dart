// lib/app/plugin_host/plugin_host_services.dart
import '../events/app_event_bus.dart';
import '../events/working_memory.dart';

/// Host-owned transient services exposed to plugins.
/// This must remain Flutter-free.
class PluginHostServices {
  final AppEventBus eventBus;
  final WorkingMemory workingMemory;

  PluginHostServices({required this.eventBus, required this.workingMemory});
}
