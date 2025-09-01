import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/config.dart';

/// Registra el prompt de llamada en debug_json_logs/ con timestamp.
Future<void> debugLogCallPrompt(
  String fileBaseName,
  Map<String, dynamic> jsonObj,
) async {
  // No escribir en producción, ni durante tests automáticos.
  if (kReleaseMode) return; // solo en debug/profile
  // Evitar crear logs durante flutter test (entorno de pruebas) o si se desactiva explícitamente.
  try {
    final raw = Config.get('DISABLE_DEBUG_JSON_LOGS', 'false');
    final disableFlag = raw.toString().toLowerCase().trim();
    // Accept common truthy values so users can set 1/true/yes/on in .env
    const truthy = {'1', 'true', 'yes', 'y', 'on'};
    if (truthy.contains(disableFlag)) return;
  } catch (_) {
    // ignore
  }
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  try {
    final dir = Directory('debug_json_logs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/call_prompt_${fileBaseName}_$ts.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonObj),
    );
  } catch (_) {
    // Silencioso en caso de error
  }
}
