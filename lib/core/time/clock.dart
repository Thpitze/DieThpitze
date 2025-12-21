// lib/core/time/clock.dart
abstract class Clock {
  DateTime nowUtc();
}

class SystemClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}