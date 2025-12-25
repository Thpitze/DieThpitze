// lib/main.dart
import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/events/app_event_bus.dart';
import 'app/events/working_memory.dart';
import 'app/plugin_host/plugin_host_services.dart';
import 'app/plugins/plugins.dart';

void main() {
  runApp(const ThpitzeApp());
}

class ThpitzeApp extends StatefulWidget {
  const ThpitzeApp({super.key});

  @override
  State<ThpitzeApp> createState() => _ThpitzeAppState();
}

class _ThpitzeAppState extends State<ThpitzeApp> {
  late final AppEventBus _eventBus;
  late final WorkingMemory _workingMemory;
  late final PluginHostServices _hostServices;

  @override
  void initState() {
    super.initState();

    _eventBus = AppEventBus();
    _workingMemory = WorkingMemory();

    _hostServices = PluginHostServices(
      eventBus: _eventBus,
      workingMemory: _workingMemory,
    );
  }

  @override
  void dispose() {
    _eventBus.dispose();
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
      home: AppShell(
        hostServices: _hostServices,
        plugins: buildPlugins(),
      ),
    );
  }
}
