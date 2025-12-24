// lib/app/plugin_api/capabilities.dart

/// Capabilities are *declared* by plugins and *granted* by the host.
/// The host may deny capabilities (e.g., read-only mode).
enum PluginCapability {
  // UI contributions
  routes,
  dashboardWidgets,
  commands,

  // Live coordination
  eventPublish,
  eventSubscribe,
  workingMemoryRead,
  workingMemoryWrite,

  // Future (reserved)
  backgroundJobs,
}
