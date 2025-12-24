// lib/app/events/app_event_bus.dart
import 'dart:async';

import 'app_event.dart';

class AppEventBus {
  final StreamController<AppEvent> _ctrl =
      StreamController<AppEvent>.broadcast(sync: true);

  void publish<E extends AppEvent>(E event) {
    if (_ctrl.isClosed) return;
    _ctrl.add(event);
  }

  Stream<E> on<E extends AppEvent>() =>
      _ctrl.stream.where((e) => e is E).cast<E>();

  Future<void> dispose() async {
    await _ctrl.close();
  }
}

@Deprecated('Use AppEventBus')
typedef InProcessAppEventBus = AppEventBus;
