import 'package:ai_chan/chat/domain/interfaces/i_chat_preferences_utils_service.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

/// Basic implementation of IChatPreferencesUtilsService for dependency injection
class BasicChatPreferencesUtilsService implements IChatPreferencesUtilsService {
  @override
  Future<String?> getString(final String key) async {
    return await PrefsUtils.getRawString(key);
  }

  @override
  Future<void> setString(final String key, final String value) async {
    await PrefsUtils.setRawString(key, value);
  }

  @override
  Future<bool?> getBool(final String key) async {
    final value = await PrefsUtils.getRawString(key);
    return value == null ? null : value.toLowerCase() == 'true';
  }

  @override
  Future<void> setBool(final String key, final bool value) async {
    await PrefsUtils.setRawString(key, value.toString());
  }

  @override
  Future<void> remove(final String key) async {
    // PrefsUtils doesn't have a remove method, so we set to empty string
    await PrefsUtils.setRawString(key, '');
  }

  @override
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool linked = false,
  }) async {
    await PrefsUtils.setGoogleAccountInfo(
      email: email,
      avatar: avatar,
      name: name,
      linked: linked,
    );
  }

  @override
  Future<void> clearGoogleAccountInfo() async {
    await PrefsUtils.clearGoogleAccountInfo();
  }

  @override
  Future<double?> getLastAutoBackupMs() async {
    final int? value = await PrefsUtils.getLastAutoBackupMs();
    return value?.toDouble();
  }

  @override
  Future<void> setEvents(final String eventsJson) async {
    await PrefsUtils.setEvents(eventsJson);
  }
}
