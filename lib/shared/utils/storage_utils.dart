import 'dart:convert';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

/// Utilidades para persistencia robusta en SharedPreferences
class StorageUtils {
  /// Guarda biografía y mensajes importados en SharedPreferences de forma robusta y centralizada
  static Future<void> saveImportedChatToPrefs(ImportedChat imported) async {
    // Use SharedPreferences to persist the provided ImportedChat in canonical keys.
    // Use PrefsUtils to centralize key names and error handling
    await PrefsUtils.setOnboardingData(jsonEncode(imported.toJson()));
    await PrefsUtils.setChatHistory(jsonEncode(imported.messages.map((m) => m.toJson()).toList()));
    // Guardar eventos programados tambi9n para compatibilidad con ChatProvider
    try {
      await PrefsUtils.setEvents(jsonEncode(imported.events.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
