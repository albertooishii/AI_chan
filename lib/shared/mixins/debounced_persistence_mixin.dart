import 'package:flutter/foundation.dart';
import 'package:ai_chan/chat/application/services/debounced_save.dart';

/// Mixin reusable that centralizes a debounced persistence helper for
/// ChangeNotifier-based providers.
///
/// Usage:
/// - call `initDebouncedPersistence(saveFunc, duration: ...)` during provider
///   initialization (e.g., constructor).
/// - call `triggerDebouncedSave()` from `notifyListeners()` overrides or
///   wherever you want to debounce persistence.
/// - call `disposeDebouncedPersistence()` from `dispose()`.
mixin DebouncedPersistenceMixin on ChangeNotifier {
  DebouncedSave? _debouncedSave;

  /// Initialize or replace the debounced save helper.
  void initDebouncedPersistence(
    Future<void> Function() saveFunc, {
    Duration duration = const Duration(seconds: 1),
  }) {
    _debouncedSave?.dispose();
    _debouncedSave = DebouncedSave(duration, saveFunc);
  }

  /// Trigger the debounced save if configured.
  void triggerDebouncedSave() => _debouncedSave?.trigger();

  /// Dispose and clear the debounced helper.
  void disposeDebouncedPersistence() {
    _debouncedSave?.dispose();
    _debouncedSave = null;
  }
}
