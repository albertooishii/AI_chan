import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/models.dart';

/// Utilidades para persistencia robusta en SharedPreferences
class StorageUtils {
  /// Guarda biografía y mensajes importados en SharedPreferences de forma robusta y centralizada
  static Future<void> saveImportedChatToPrefs(ImportedChat imported) async {
    final prefs = await SharedPreferences.getInstance();
    // Guardar el JSON robusto completo (biografía + mensajes) en onboarding_data
    await prefs.setString('onboarding_data', jsonEncode(imported.toJson()));
    await prefs.setString('chat_history', jsonEncode(imported.messages.map((m) => m.toJson()).toList()));
    // Guardar eventos programados también para compatibilidad con ChatProvider
    try {
      await prefs.setString('events', jsonEncode(imported.events.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
