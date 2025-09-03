import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/config.dart';

/// Centraliza accesos a SharedPreferences usados en múltiples partes del app.
class PrefsUtils {
  // --- Canonical key constants ---
  static const kSelectedAudioProvider = 'selected_audio_provider';
  static const kSelectedModel = 'selected_model';
  static const kOnboardingData = 'onboarding_data';
  static const kChatHistory = 'chat_history';
  static const kEvents = 'events';
  static const kChatFullExport = 'chat_full_export';
  static const kVoiceCalls = 'calls'; // Renombrado de voice_calls a calls

  // --- Dynamic key factories ---
  static String callMessagesKey(String callId) =>
      'call_messages_$callId'; // Renombrado

  // Mantener compatibilidad hacia atrás temporalmente
  static String voiceMessagesKey(String callId) => callMessagesKey(callId);

  /// Ensure default values for audio provider and model keys exist.
  static Future<void> ensureDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProvider = prefs.getString('selected_audio_provider');
      if (savedProvider == null || savedProvider.isEmpty) {
        final env = Config.getAudioProvider().toLowerCase();
        String defaultProvider = 'google';
        if (env == 'openai') {
          defaultProvider = 'openai';
        }
        if (env == 'gemini') {
          defaultProvider = 'google';
        }
        await prefs.setString('selected_audio_provider', defaultProvider);
      }

      final savedModel = prefs.getString('selected_model');
      if (savedModel == null || savedModel.isEmpty) {
        final defModel = Config.getDefaultTextModel();
        if (defModel.isNotEmpty) {
          await prefs.setString('selected_model', defModel);
        }
      }

      final provider =
          prefs.getString('selected_audio_provider') ??
          Config.getAudioProvider().toLowerCase();
      final providerKey = 'selected_voice_$provider';
      final providerVoice = prefs.getString(providerKey);
      if (providerVoice == null || providerVoice.isEmpty) {
        String defaultVoice = '';
        if (provider == 'google') {
          defaultVoice = Config.getGoogleVoice();
        }
        if (provider == 'openai') {
          defaultVoice = Config.getOpenaiVoice();
        }
        if (defaultVoice.isNotEmpty) {
          await prefs.setString(providerKey, defaultVoice);
        }
      }
    } catch (_) {}
  }

  static Future<String> getSelectedAudioProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_audio_provider');
      final envValue = Config.getAudioProvider().toLowerCase();
      String defaultValue = 'google';
      if (envValue == 'openai') {
        defaultValue = 'openai';
      }
      if (envValue == 'gemini') {
        defaultValue = 'google';
      }
      final resolved = (saved ?? defaultValue).toLowerCase();
      if (resolved == 'gemini') return 'google';
      return resolved;
    } catch (_) {
      return 'google';
    }
  }

  static Future<String?> getSelectedVoiceForProvider(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerKey = 'selected_voice_${provider.toLowerCase()}';
      return prefs.getString(providerKey);
    } catch (_) {
      return null;
    }
  }

  /// Devuelve la voz preferida para el provider actualmente seleccionado.
  /// Si no hay voz configurada para el provider, devuelve [fallback].
  /// Centraliza la lógica repetida usada en varios sitios (ej. mapeos y
  /// comprobaciones de cadena vacía).
  static Future<String> getPreferredVoice({String fallback = 'nova'}) async {
    try {
      final provider = await getSelectedAudioProvider();
      final providerVoice = await getSelectedVoiceForProvider(provider);
      if (providerVoice != null && providerVoice.trim().isNotEmpty) {
        return providerVoice;
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> setSelectedAudioProvider(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_audio_provider', provider);
    } catch (_) {}
  }

  static Future<void> setSelectedVoiceForProvider(
    String provider,
    String voice,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerKey = 'selected_voice_${provider.toLowerCase()}';
      await prefs.setString(providerKey, voice);
    } catch (_) {}
  }

  static Future<String?> getSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('selected_model');
    } catch (_) {
      return null;
    }
  }

  /// Devuelve el modelo seleccionado o el valor por defecto de `Config` si
  /// no hay ninguno guardado. Siempre devuelve una cadena (puede estar vacía
  /// si Config no provee un valor por defecto).
  static Future<String> getSelectedModelOrDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_model');
      if (saved != null && saved.trim().isNotEmpty) return saved;
      final def = Config.getDefaultTextModel();
      return def;
    } catch (_) {
      return Config.getDefaultTextModel();
    }
  }

  static Future<void> setSelectedModel(String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_model', model);
    } catch (_) {}
  }

  // --- Google account convenience helpers ---
  static Future<void> setGoogleAccountInfo({
    String? email,
    String? avatar,
    String? name,
    required bool linked,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null) {
        await prefs.setString('google_account_email', email);
      } else {
        await prefs.remove('google_account_email');
      }
      if (avatar != null) {
        await prefs.setString('google_account_avatar', avatar);
      } else {
        await prefs.remove('google_account_avatar');
      }
      if (name != null) {
        await prefs.setString('google_account_name', name);
      } else {
        await prefs.remove('google_account_name');
      }
      await prefs.setBool('google_account_linked', linked);
    } catch (_) {}
  }

  static Future<void> clearGoogleAccountInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('google_account_email');
      await prefs.remove('google_account_avatar');
      await prefs.remove('google_account_name');
      await prefs.remove('google_account_linked');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getGoogleAccountInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'email': prefs.getString('google_account_email'),
        'avatar': prefs.getString('google_account_avatar'),
        'name': prefs.getString('google_account_name'),
        'linked': prefs.getBool('google_account_linked') ?? false,
      };
    } catch (_) {
      return {'email': null, 'avatar': null, 'name': null, 'linked': false};
    }
  }

  // --- Onboarding / chat persistence helpers (centralize keys) ---
  static Future<String?> getOnboardingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('onboarding_data');
    } catch (_) {
      return null;
    }
  }

  static Future<void> setOnboardingData(String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('onboarding_data', json);
    } catch (_) {}
  }

  static Future<void> removeOnboardingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('onboarding_data');
    } catch (_) {}
  }

  static Future<String?> getChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('chat_history');
    } catch (_) {
      return null;
    }
  }

  static Future<void> setChatHistory(String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_history', json);
    } catch (_) {}
  }

  static Future<void> removeChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_history');
    } catch (_) {}
  }

  static Future<String?> getEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('events');
    } catch (_) {
      return null;
    }
  }

  static Future<void> setEvents(String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('events', json);
    } catch (_) {}
  }

  static Future<void> setFullExport(String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kChatFullExport, json);
    } catch (_) {}
  }

  // --- Generic raw access helpers ---
  /// Get a raw string by key. Useful for callers that manage their own key naming.
  static Future<String?> getRawString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// Set a raw string by key.
  static Future<void> setRawString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  /// Remove an arbitrary key from prefs.
  static Future<void> removeKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  // --- Auto-backup timestamp helpers ---
  static const kLastAutoBackupMs = 'last_auto_backup_ms';

  /// Returns the milliseconds-since-epoch of the last successful automatic
  /// backup, or null if never set.
  static Future<int?> getLastAutoBackupMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(kLastAutoBackupMs);
    } catch (_) {
      return null;
    }
  }

  /// Persist the timestamp (ms since epoch) of the last successful automatic backup.
  static Future<void> setLastAutoBackupMs(int ms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kLastAutoBackupMs, ms);
    } catch (_) {}
  }
}
