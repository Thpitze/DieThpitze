// lib/main.dart
//
// App entry point: boots MaterialApp and injects the CoreAdapter implementation.

import 'package:flutter/material.dart';

import 'package:thpitze_main/app/core_adapter_impl.dart';
import 'package:thpitze_main/app/main_window.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final adapter = CoreAdapterImpl.defaultForApp();

  runApp(ThpitzeApp(adapter: adapter));
}

class ThpitzeApp extends StatelessWidget {
  final CoreAdapterImpl adapter;

  const ThpitzeApp({
    super.key,
    required this.adapter,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thpitze',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: MainWindow(adapter: adapter),
    );
  }
}
