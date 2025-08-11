import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Registra el prompt de llamada en debug_json_logs/ con timestamp.
Future<void> debugLogCallPrompt(String fileBaseName, Map<String, dynamic> jsonObj) async {
  if (kReleaseMode) return; // solo en debug/profile
  try {
    final dir = Directory('debug_json_logs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/call_prompt_${fileBaseName}_$ts.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonObj), mode: FileMode.write);
  } catch (_) {
    // Silencioso en caso de error
  }
}
