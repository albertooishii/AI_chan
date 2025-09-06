import 'dart:async';

/// Small helper that debounces calls to an async save function.
class DebouncedSave {
  DebouncedSave(this.duration, this.save);
  final Duration duration;
  final Future<void> Function() save;
  Timer? _timer;

  /// Trigger the debounced save. Subsequent calls within [duration] reset the timer.
  void trigger() {
    _timer?.cancel();
    _timer = Timer(duration, () {
      try {
        save();
      } catch (_) {}
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
