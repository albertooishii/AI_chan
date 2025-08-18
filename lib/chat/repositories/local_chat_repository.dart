import 'dart:convert';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/utils/storage_utils.dart';
import 'package:ai_chan/core/models/index.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';

/// Implementación ligera de IChatRepository delegando en StorageUtils y SharedPreferences.
class LocalChatRepository implements IChatRepository {
  @override
  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr) async {
    try {
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      // Guardar usando StorageUtils wrapper que guarda onboarding_data y chat_history
      final imported = models.ImportedChat.fromJson(parsed);
      await StorageUtils.saveImportedChatToPrefs(imported);
      return parsed;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> exportAllToJson(Map<String, dynamic> exportedJson) async {
    final encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(exportedJson);
  }

  @override
  Future<void> saveAll(Map<String, dynamic> exportedJson) async {
    try {
      final imported = models.ImportedChat.fromJson(exportedJson);
      await StorageUtils.saveImportedChatToPrefs(imported);
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>?> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final bioString = prefs.getString('onboarding_data');
    final jsonString = prefs.getString('chat_history');
    if (bioString == null && jsonString == null) return null;
    try {
      final profile = bioString != null ? jsonDecode(bioString) as Map<String, dynamic> : <String, dynamic>{};
      final messages = jsonString != null ? jsonDecode(jsonString) as List<dynamic> : <dynamic>[];
      return {'profile': profile, 'messages': messages};
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_history');
    await prefs.remove('onboarding_data');
  }
}
