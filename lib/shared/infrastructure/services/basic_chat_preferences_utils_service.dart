import 'package:ai_chan/chat/domain/interfaces/i_chat_preferences_utils_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Basic implementation of chat preferences utilities service
class BasicChatPreferencesUtilsService implements IChatPreferencesUtilsService {
  @override
  Future<String?> getString(final String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> setString(final String key, final String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Future<bool?> getBool(final String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  @override
  Future<void> setBool(final String key, final bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Future<void> remove(final String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool? linked,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (email != null) await prefs.setString('google_email', email);
    if (avatar != null) await prefs.setString('google_avatar', avatar);
    if (name != null) await prefs.setString('google_name', name);
    if (linked != null) await prefs.setBool('google_linked', linked);
  }

  @override
  Future<void> clearGoogleAccountInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_email');
    await prefs.remove('google_avatar');
    await prefs.remove('google_name');
    await prefs.remove('google_linked');
  }

  @override
  Future<double?> getLastAutoBackupMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('last_auto_backup_ms');
  }

  @override
  Future<void> setEvents(final String eventsJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('events', eventsJson);
  }
}
