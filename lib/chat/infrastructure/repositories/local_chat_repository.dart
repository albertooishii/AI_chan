import 'dart:convert';

import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implementación única y consolidada de IChatRepository.
/// Usa StorageUtils (si está disponible) para compatibilidad con import/export robusto.
/// Persiste partes estructuradas en SharedPreferences y guarda un respaldo completo
/// bajo la clave 'chat_full_export' para inspección manual si es necesario.
class LocalChatRepository implements IChatRepository {
  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_history');
    await prefs.remove('onboarding_data');
    await prefs.remove('chat_full_export');
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

    // No legacy single-key fallback: return null if structured keys are not present
    return null;
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
    // Save structured parts if possible to make future reads deterministic
    if (exportedJson.containsKey('messages')) {
      await prefs.setString('chat_history', json.encode(exportedJson['messages']));
    }
    if (exportedJson.containsKey('onboarding') ||
        exportedJson.containsKey('ai_profile') ||
        exportedJson.containsKey('aiChanProfile')) {
      // Many callers use 'onboarding' or profile top-level keys; save a canonical 'onboarding_data'
      final profile = exportedJson['onboarding'] ?? exportedJson['ai_profile'] ?? exportedJson['aiChanProfile'];
      if (profile != null) {
        await prefs.setString('onboarding_data', json.encode(profile));
      }
    }
    // Fallback: persist the whole payload under 'chat_full_export' for manual inspection
    await prefs.setString('chat_full_export', json.encode(exportedJson));
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
