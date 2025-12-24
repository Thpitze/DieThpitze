// lib/main.dart
import 'package:flutter/material.dart';

import 'app/events/app_event_bus.dart';
import 'app/events/working_memory.dart';
import 'app/plugin_host/plugin_registry.dart';

void main() {
  runApp(const ThpitzeApp());
}

/// App host root.
/// Owns volatile host services (event bus + working memory) and disposes them.
class ThpitzeApp extends StatefulWidget {
  const ThpitzeApp({super.key});

  @override
  State<ThpitzeApp> createState() => _ThpitzeAppState();
}

class _ThpitzeAppState extends State<ThpitzeApp> {
  late final AppEventBus _eventBus;
  late final WorkingMemory _workingMemory;
  late final PluginRegistry _pluginRegistry;

  @override
  void initState() {
    super.initState();

    _eventBus = AppEventBus();
    _workingMemory = WorkingMemory();
    _pluginRegistry = PluginRegistry();

    // Phase 1: no plugins registered yet (compile-time list later).
    // _pluginRegistry.register(SomePlugin(), grants: {...});
  }

  @override
  void dispose() {
    _eventBus.dispose(); // async; fire-and-forget is fine on shutdown
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thpitze',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomePage(
        pluginRegistry: _pluginRegistry,
        workingMemory: _workingMemory,
      ),
    );
  }
}

/// Temporary placeholder shell.
/// Next step will be: AppShell that renders plugin-provided screens.
class HomePage extends StatelessWidget {
  final PluginRegistry pluginRegistry;
  final WorkingMemory workingMemory;

  const HomePage({
    super.key,
    required this.pluginRegistry,
    required this.workingMemory,
  });

  @override
  Widget build(BuildContext context) {
    final pluginCount = pluginRegistry.all.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Thpitze')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Host wired.\n'
          'Registered plugins: $pluginCount\n'
          'WorkingMemory strictTypeMismatch: ${workingMemory.strictTypeMismatch}',
        ),
      ),
    );
  }
}
