import 'package:ai_chan/chat/domain/interfaces/i_preferences_service.dart';
import 'package:ai_chan/shared.dart';

/// Implementación real de IPreferencesService que usa SharedPreferences a través de PrefsUtils
class RealPreferencesService implements IPreferencesService {
  @override
  Future<void> setSelectedModel(final String model) async {
    await PrefsUtils.setSelectedModel(model);
  }

  @override
  Future<String?> getSelectedModel() async {
    return await PrefsUtils.getSelectedModel();
  }

  @override
  Future<void> setSelectedAudioProvider(final String provider) async {
    await PrefsUtils.setSelectedAudioProvider(provider);
  }

  @override
  Future<String?> getSelectedAudioProvider() async {
    return await PrefsUtils.getSelectedAudioProvider();
  }

  @override
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool? linked,
  }) async {
    await PrefsUtils.setGoogleAccountInfo(
      email: email,
      avatar: avatar,
      name: name,
      linked: linked ?? false,
    );
  }

  @override
  Future<void> clearGoogleAccountInfo() async {
    await PrefsUtils.clearGoogleAccountInfo();
  }

  @override
  Future<Map<String, dynamic>> getGoogleAccountInfo() async {
    return await PrefsUtils.getGoogleAccountInfo();
  }

  @override
  Future<int?> getLastAutoBackupMs() async {
    return await PrefsUtils.getLastAutoBackupMs();
  }

  @override
  Future<void> setLastAutoBackupMs(final int timestamp) async {
    await PrefsUtils.setLastAutoBackupMs(timestamp);
  }

  @override
  Future<String> getEvents() async {
    return await PrefsUtils.getEvents() ?? '[]';
  }

  @override
  Future<void> setEvents(final String eventsJson) async {
    await PrefsUtils.setEvents(eventsJson);
  }
}
