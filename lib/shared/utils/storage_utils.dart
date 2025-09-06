import 'dart:convert';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

/// Utilidades para persistencia robusta en SharedPreferences
class StorageUtils {
  /// Guarda biografía y mensajes exportados en SharedPreferences de forma robusta y centralizada
  static Future<void> saveChatExportToPrefs(final ChatExport exported) async {
    // Use SharedPreferences to persist the provided ChatExport in canonical keys.
    // Use PrefsUtils to centralize key names and error handling
    await PrefsUtils.setOnboardingData(jsonEncode(exported.toJson()));
    await PrefsUtils.setChatHistory(
      jsonEncode(exported.messages.map((final m) => m.toJson()).toList()),
    );
    // Guardar eventos programados también para compatibilidad con ChatProvider
    try {
      await PrefsUtils.setEvents(
        jsonEncode(exported.events.map((final e) => e.toJson()).toList()),
      );
    } on Exception catch (_) {}
  }
}
