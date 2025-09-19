import 'dart:convert';
import 'package:ai_chan/shared.dart';

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
    // Guardar timeline también para asegurar que se persiste correctamente
    try {
      await PrefsUtils.setTimeline(
        jsonEncode(exported.timeline.map((final t) => t.toJson()).toList()),
      );
    } on Exception catch (_) {}
  }
}
