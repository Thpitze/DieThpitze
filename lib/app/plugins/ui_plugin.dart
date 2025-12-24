import 'package:flutter/widgets.dart';

import '../core_adapter_impl.dart';
import '../events/app_event_bus.dart';
import '../events/working_memory.dart';

abstract class UiPlugin {
  String get pluginId;
  String get displayName;

  Widget buildScreen({
    required CoreAdapterImpl adapter,
    required AppEventBus eventBus,
    required WorkingMemory workingMemory,
  });
}
