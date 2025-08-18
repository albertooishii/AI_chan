import 'dart:convert';
import 'dart:io';

import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/utils/storage_utils.dart';
import 'package:path_provider/path_provider.dart';
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
        final profile = bioString != null ? jsonDecode(bioString) as Map<String, dynamic> : <String, dynamic>{};
        final messages = jsonString != null ? jsonDecode(jsonString) as List<dynamic> : <dynamic>[];
        return {'profile': profile, 'messages': messages};
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
    final encoded = json.encode(exportedJson);
    // Try to write a file in documents directory
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ai_chan_chat_export_${DateTime.now().toIso8601String()}.json');
      await file.writeAsString(encoded);
      return file.path;
    } catch (_) {
      // Fallback to returning the JSON string
      return encoded;
    }
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
