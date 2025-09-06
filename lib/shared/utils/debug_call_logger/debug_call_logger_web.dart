import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// No-op en web para evitar errores de IO.
Future<void> debugLogCallPrompt(
  final String fileBaseName,
  final Map<String, dynamic> jsonObj,
) async {
  if (kReleaseMode) return;
  // Mostrar en consola del navegador
  Log.d('[debugLogCallPrompt][$fileBaseName]: $jsonObj');
}
