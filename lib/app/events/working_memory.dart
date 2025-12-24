// lib/app/events/working_memory.dart
import 'dart:async';

enum WorkingMemoryScope { session, vault }

typedef WorkingMemoryKey = String;

/// Volatile, typed key-value store with stream watchers.
/// - session scope: survives vault switches
/// - vault scope: reset on vault open/change
class WorkingMemory {
  final _session = _ScopedStore();
  final _vault = _ScopedStore();

  /// v1 default: tolerant (mismatch => null).
  bool strictTypeMismatch = false;

  void resetVaultScope() => _vault.clearAll();

  T? get<T>(WorkingMemoryScope scope, WorkingMemoryKey key) {
    final Object? v = _store(scope).getRaw(key);
    if (v == null) return null;

    if (v is T) {
      // IMPORTANT: explicit cast required; analyzer doesn't promote with type param T.
      return v as T;
    }

    if (strictTypeMismatch) {
      throw StateError('WorkingMemory type mismatch for "$key": ${v.runtimeType} != $T');
    }
    return null;
  }

  void set<T>(WorkingMemoryScope scope, WorkingMemoryKey key, T value) {
    _store(scope).setRaw(key, value);
  }

  void remove(WorkingMemoryScope scope, WorkingMemoryKey key) {
    _store(scope).remove(key);
  }

  /// Emits current value immediately (nullable), then future updates.
  Stream<T?> watch<T>(WorkingMemoryScope scope, WorkingMemoryKey key) {
    return _store(scope).watchKey(key).map((Object? v) {
      if (v == null) return null;

      if (v is T) {
        // Same issue: explicit cast avoids return-of-invalid-type-from-closure.
        return v as T;
      }

      if (strictTypeMismatch) {
        throw StateError('WorkingMemory type mismatch for "$key": ${v.runtimeType} != $T');
      }
      return null;
    });
  }

  _ScopedStore _store(WorkingMemoryScope scope) =>
      scope == WorkingMemoryScope.session ? _session : _vault;
}

class _ScopedStore {
  final Map<WorkingMemoryKey, Object?> _data = {};
  final Map<WorkingMemoryKey, StreamController<Object?>> _watchers = {};

  Object? getRaw(WorkingMemoryKey key) => _data[key];

  void setRaw(WorkingMemoryKey key, Object? value) {
    _data[key] = value;
    _watcher(key).add(value);
  }

  void remove(WorkingMemoryKey key) {
    _data.remove(key);
    _watcher(key).add(null);
  }

  void clearAll() {
    final keys = _data.keys.toList(growable: false);
    _data.clear();
    for (final k in keys) {
      _watcher(k).add(null);
    }
  }

  Stream<Object?> watchKey(WorkingMemoryKey key) {
    final ctrl = _watcher(key);
    return Stream<Object?>.multi((multi) {
      multi.add(_data[key]); // immediate
      final sub = ctrl.stream.listen(multi.add, onError: multi.addError);
      multi.onCancel = sub.cancel;
    });
  }

  StreamController<Object?> _watcher(WorkingMemoryKey key) {
    return _watchers.putIfAbsent(
      key,
      () => StreamController<Object?>.broadcast(sync: true),
    );
  }
}

/// Compatibility alias for old code paths.
@Deprecated('Use WorkingMemory')
typedef InMemoryWorkingMemory = WorkingMemory;
