import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/infrastructure/config/config.dart';

/// Registra el prompt de llamada en debug_json_logs/ con timestamp.
Future<void> debugLogCallPrompt(
  final String fileBaseName,
  final Map<String, dynamic> jsonObj,
) async {
  // No escribir en producción, ni durante tests automáticos.
  if (kReleaseMode) return; // solo en debug/profile
  // Evitar crear logs durante flutter test (entorno de pruebas) o si se desactiva explícitamente.
  try {
    final debugMode = Config.get('DEBUG_MODE', '').toLowerCase().trim();
    // Solo crear JSON logs en modo 'full'
    if (debugMode != 'full') return;
  } on Exception catch (_) {
    // Si no se puede leer la config, no crear logs por seguridad
    return;
  }
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  try {
    final dir = Directory('debug_json_logs');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/call_prompt_${fileBaseName}_$ts.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonObj),
    );
  } on Exception catch (_) {
    // Silencioso en caso de error
  }
}
