import 'package:shared_preferences/shared_preferences.dart';

/// Utilities to initialize SharedPreferences in tests consistently.
/// Central place to add common pref keys used across tests.
class PrefsTestUtils {
  /// Return a minimal set of mock prefs useful for most tests.
  static Map<String, Object> defaultMockValues() {
    return <String, Object>{
      // Add any defaults that tests rely on (empty by default)
    };
  }

  /// Set mock initial values for SharedPreferences in tests.
  /// If [prefs] is null, the defaultMockValues() map is used.
  static void setMockInitialValues([final Map<String, Object>? prefs]) {
    SharedPreferences.setMockInitialValues(prefs ?? defaultMockValues());
  }
}
