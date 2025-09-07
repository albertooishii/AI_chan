/// 🎯 **Chat Preferences Utils Service Interface** - Domain Abstraction for Preferences Operations
///
/// Defines the contract for preferences utility operations within the chat bounded context.
/// This ensures bounded context isolation while providing preferences functionality.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatPreferencesUtilsService {
  /// Gets a string value from preferences
  Future<String?> getString(final String key);

  /// Sets a string value in preferences
  Future<void> setString(final String key, final String value);

  /// Gets a boolean value from preferences
  Future<bool?> getBool(final String key);

  /// Sets a boolean value in preferences
  Future<void> setBool(final String key, final bool value);

  /// Removes a key from preferences
  Future<void> remove(final String key);

  /// Sets Google account info
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool linked,
  });

  /// Clears Google account info
  Future<void> clearGoogleAccountInfo();

  /// Gets last auto backup milliseconds
  Future<double?> getLastAutoBackupMs();

  /// Sets events as JSON string
  Future<void> setEvents(final String eventsJson);
}
