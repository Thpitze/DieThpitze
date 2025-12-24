// lib/app/plugin_api/host_services.dart
import '../events/app_event_bus.dart';
import '../events/working_memory.dart';

/// Host-provided services available to plugins.
///
/// Contract rules:
/// - UI-agnostic: no Flutter imports here.
/// - Volatile: event bus + working memory do not persist across restarts.
/// - Working memory vault-scope is cleared on vault change by the app host.
class PluginHostServices {
  final int hostApiMajor;
  final AppEventBus eventBus;
  final WorkingMemory workingMemory;

  const PluginHostServices({
    required this.hostApiMajor,
    required this.eventBus,
    required this.workingMemory,
  });
}
