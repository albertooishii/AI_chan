import 'package:ai_chan/chat/domain/interfaces/i_preferences_service.dart';

/// Basic implementation of IPreferencesService for dependency injection
class BasicPreferencesService implements IPreferencesService {
  final Map<String, dynamic> _storage = {};

  @override
  Future<String?> getSelectedModel() async {
    return _storage['selectedModel'] as String?;
  }

  @override
  Future<void> setSelectedModel(final String model) async {
    _storage['selectedModel'] = model;
  }

  @override
  Future<Map<String, dynamic>?> getGoogleAccountInfo() async {
    return _storage['googleAccount'] as Map<String, dynamic>?;
  }

  @override
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool? linked,
  }) async {
    _storage['googleAccount'] = {
      'email': email,
      'avatar': avatar,
      'name': name,
      'linked': linked,
    };
  }

  @override
  Future<void> clearGoogleAccountInfo() async {
    _storage.remove('googleAccount');
  }

  @override
  Future<String?> getSelectedAudioProvider() async {
    return _storage['audioProvider'] as String?;
  }

  @override
  Future<void> setSelectedAudioProvider(final String provider) async {
    _storage['audioProvider'] = provider;
  }

  @override
  Future<String?> getEvents() async {
    return _storage['events'] as String?;
  }

  @override
  Future<void> setEvents(final String eventsJson) async {
    _storage['events'] = eventsJson;
  }

  @override
  Future<int?> getLastAutoBackupMs() async {
    return _storage['lastAutoBackupMs'] as int?;
  }

  @override
  Future<void> setLastAutoBackupMs(final int timestamp) async {
    _storage['lastAutoBackupMs'] = timestamp;
  }
}
