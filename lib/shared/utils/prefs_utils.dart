import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';

/// Centraliza accesos a SharedPreferences usados en múltiples partes del app.
/// ✅ MIGRADO: Usa configuración YAML para proveedores de audio y voces
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
  static String callMessagesKey(final String callId) =>
      'call_messages_$callId'; // Renombrado

  // Mantener compatibilidad hacia atrás temporalmente
  static String voiceMessagesKey(final String callId) =>
      callMessagesKey(callId);

  /// Ensure default values for audio provider and model keys exist.
  static Future<void> ensureDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProvider = prefs.getString('selected_audio_provider');
      if (savedProvider == null || savedProvider.isEmpty) {
        // ✅ YAML: Usar nueva configuración YAML
        final defaultProvider =
            AIProviderConfigLoader.getDefaultAudioProvider();
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
          AIProviderConfigLoader.getDefaultAudioProvider();
      final providerKey = 'selected_voice_$provider';
      final providerVoice = prefs.getString(providerKey);
      if (providerVoice == null || providerVoice.isEmpty) {
        // ✅ YAML: Usar nueva configuración YAML para voces
        final defaultVoice = AIProviderConfigLoader.getDefaultVoiceForProvider(
          provider,
        );
        if (defaultVoice != null && defaultVoice.isNotEmpty) {
          await prefs.setString(providerKey, defaultVoice);
        }
      }
    } on Exception catch (_) {}
  }

  static Future<String> getSelectedAudioProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_audio_provider');

      // ✅ YAML: Usar nueva configuración YAML para obtener el provider por defecto
      final defaultValue = AIProviderConfigLoader.getDefaultAudioProvider();

      final resolved = (saved ?? defaultValue).toLowerCase();
      // Mantener compatibilidad hacia atrás: 'gemini' -> 'google'
      if (resolved == 'gemini') return 'google';
      return resolved;
    } on Exception catch (_) {
      return 'google';
    }
  }

  static Future<String?> getSelectedVoiceForProvider(
    final String provider,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerKey = 'selected_voice_${provider.toLowerCase()}';
      return prefs.getString(providerKey);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Devuelve la voz preferida para el provider actualmente seleccionado.
  /// Si no hay voz configurada para el provider, devuelve [fallback].
  /// Centraliza la lógica repetida usada en varios sitios (ej. mapeos y
  /// comprobaciones de cadena vacía).
  static Future<String> getPreferredVoice({
    final String fallback = 'nova',
  }) async {
    try {
      final provider = await getSelectedAudioProvider();
      final providerVoice = await getSelectedVoiceForProvider(provider);
      if (providerVoice != null && providerVoice.trim().isNotEmpty) {
        return providerVoice;
      }
      return fallback;
    } on Exception catch (_) {
      return fallback;
    }
  }

  static Future<void> setSelectedAudioProvider(final String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_audio_provider', provider);
    } on Exception catch (_) {}
  }

  static Future<void> setSelectedVoiceForProvider(
    final String provider,
    final String voice,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerKey = 'selected_voice_${provider.toLowerCase()}';
      await prefs.setString(providerKey, voice);
    } on Exception catch (_) {}
  }

  static Future<String?> getSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('selected_model');
    } on Exception catch (_) {
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
    } on Exception catch (_) {
      return Config.getDefaultTextModel();
    }
  }

  static Future<void> setSelectedModel(final String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_model', model);
    } on Exception catch (_) {}
  }

  // --- Google account convenience helpers ---
  static Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    required final bool linked,
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
    } on Exception catch (_) {}
  }

  static Future<void> clearGoogleAccountInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('google_account_email');
      await prefs.remove('google_account_avatar');
      await prefs.remove('google_account_name');
      await prefs.remove('google_account_linked');
    } on Exception catch (_) {}
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
    } on Exception catch (_) {
      return {'email': null, 'avatar': null, 'name': null, 'linked': false};
    }
  }

  // --- Onboarding / chat persistence helpers (centralize keys) ---
  static Future<String?> getOnboardingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('onboarding_data');
    } on Exception catch (_) {
      return null;
    }
  }

  static Future<void> setOnboardingData(final String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('onboarding_data', json);
    } on Exception catch (_) {}
  }

  static Future<void> removeOnboardingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('onboarding_data');
    } on Exception catch (_) {}
  }

  static Future<String?> getChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('chat_history');
    } on Exception catch (_) {
      return null;
    }
  }

  static Future<void> setChatHistory(final String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_history', json);
    } on Exception catch (_) {}
  }

  static Future<void> removeChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_history');
    } on Exception catch (_) {}
  }

  static Future<String?> getEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('events');
    } on Exception catch (_) {
      return null;
    }
  }

  static Future<void> setEvents(final String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('events', json);
    } on Exception catch (_) {}
  }

  static Future<String?> getTimeline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('timeline');
    } on Exception catch (_) {
      return null;
    }
  }

  static Future<void> setTimeline(final String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('timeline', json);
    } on Exception catch (_) {}
  }

  static Future<void> setFullExport(final String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kChatFullExport, json);
    } on Exception catch (_) {}
  }

  // --- Generic raw access helpers ---
  /// Get a raw string by key. Useful for callers that manage their own key naming.
  static Future<String?> getRawString(final String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Set a raw string by key.
  static Future<void> setRawString(final String key, final String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } on Exception catch (_) {}
  }

  /// Remove an arbitrary key from prefs.
  static Future<void> removeKey(final String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } on Exception catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } on Exception catch (_) {}
  }

  // --- Auto-backup timestamp helpers ---
  static const kLastAutoBackupMs = 'last_auto_backup_ms';

  /// Returns the milliseconds-since-epoch of the last successful automatic
  /// backup, or null if never set.
  static Future<int?> getLastAutoBackupMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(kLastAutoBackupMs);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Persist the timestamp (ms since epoch) of the last successful automatic backup.
  static Future<void> setLastAutoBackupMs(final int ms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kLastAutoBackupMs, ms);
    } on Exception catch (_) {}
  }
}
