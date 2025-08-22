import 'dart:convert';

import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implementación única y consolidada de IChatRepository.
/// Usa StorageUtils (si está disponible) para compatibilidad con import/export robusto.
/// Además mantiene un respaldo en SharedPreferences bajo la clave 'chat_state_v1'.
class LocalChatRepository implements IChatRepository {
  static const _kPrefsKey = 'chat_state_v1';

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_history');
    await prefs.remove('onboarding_data');
    await prefs.remove(_kPrefsKey);
  }

  @override
  Future<Map<String, dynamic>?> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Prefer the structured onboarding + chat_history if present
    final bioString = prefs.getString('onboarding_data');
    final jsonString = prefs.getString('chat_history');
    if (bioString != null || jsonString != null) {
      try {
        // El onboarding_data puede ser el JSON completo (profile + messages/events) o solo el profile.
        final Map<String, dynamic> profileMap = bioString != null
            ? (jsonDecode(bioString) as Map<String, dynamic>)
            : <String, dynamic>{};
        final List<dynamic> messages = jsonString != null ? jsonDecode(jsonString) as List<dynamic> : <dynamic>[];
        // Normalizar la salida para que sea compatible con ImportedChat.fromJson:
        // devolver un mapa con los campos del perfil en el nivel superior y las claves 'messages' y 'events'.
        final Map<String, dynamic> out = Map<String, dynamic>.from(profileMap);
        out['messages'] = messages;
        // Si no existen events en el profileMap, intentar tomar events desde el propio JSON guardado
        if (!out.containsKey('events')) {
          out['events'] = <dynamic>[];
        }
        return out;
      } catch (_) {}
    }

    // Fallback: legacy single-key storage
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return null;
    try {
      final Map<String, dynamic> parsed = json.decode(raw) as Map<String, dynamic>;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAll(Map<String, dynamic> exportedJson) async {
    // Prefer to save using StorageUtils if we can map to ImportedChat
    try {
      final imported = ImportedChat.fromJson(exportedJson);
      await StorageUtils.saveImportedChatToPrefs(imported);
      return;
    } catch (_) {
      // ignore and fallthrough to raw save
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(exportedJson);
    await prefs.setString(_kPrefsKey, encoded);
  }

  @override
  Future<String> exportAllToJson(Map<String, dynamic> exportedJson) async {
    // Format the JSON with indentation for better readability
    const encoder = JsonEncoder.withIndent('  ');
    final encoded = encoder.convert(exportedJson);
    // Always return the JSON string content, not a file path
    // The caller (UI) will handle saving to file if needed
    return encoded;
  }

  @override
  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr) async {
    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      await saveAll(parsed);
      return parsed;
    } catch (_) {
      return null;
    }
  }
}
