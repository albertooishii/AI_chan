import 'package:flutter/foundation.dart';

/// No-op en web para evitar errores de IO.
Future<void> debugLogCallPrompt(String fileBaseName, Map<String, dynamic> jsonObj) async {
  if (kReleaseMode) return;
  // Mostrar en consola del navegador
  debugPrint('[debugLogCallPrompt][$fileBaseName]: $jsonObj');
}
