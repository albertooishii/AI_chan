import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Controlador sencillo para manejar subtítulos de IA y usuario.
/// Encapsula timers de auto-clear, normalización mínima y logging opcional.
class SubtitleController {
  SubtitleController({bool debug = false}) : _debug = debug;

  bool _debug;
  bool get debug => _debug;
  void setDebug(bool value) => _debug = value;

  final ValueNotifier<String> ai = ValueNotifier<String>('');
  final ValueNotifier<String> user = ValueNotifier<String>('');

  Timer? _aiClearTimer;
  Timer? _userClearTimer;

  void dispose() {
    _aiClearTimer?.cancel();
    _userClearTimer?.cancel();
    ai.dispose();
    user.dispose();
  }

  void clearAll() {
    _aiClearTimer?.cancel();
    _userClearTimer?.cancel();
    if (ai.value.isNotEmpty) ai.value = '';
    if (user.value.isNotEmpty) user.value = '';
  }

  /// Normalización mínima de texto para mostrar al usuario.
  String _normalize(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ');
    cleaned = cleaned.replaceAllMapped(RegExp(r'([¡¿])\s+([A-Za-zÁÉÍÓÚáéíóúÑñ])'), (m) => '${m.group(1)}${m.group(2)}');
    return cleaned;
  }

  void _logRaw(String text) {
    if (!_debug) return;
    debugPrint('👁️ [SUB-RAW] len=${text.length} -> "$text"');
  }

  /// Actualiza fragmento de IA aplicando gating externo.
  /// [firstAudioReceived] evita mostrar texto antes de oír la IA.
  /// [suppressFurther] permite cortar tras end_call / rechazo.
  void handleAiChunk(String chunk, {required bool firstAudioReceived, required bool suppressFurther}) {
    _logRaw(chunk);
    if (chunk == '__REVEAL__') return; // sentinel antiguo (ignorar)
    if (!firstAudioReceived) return; // no mostrar antes del primer audio
    if (suppressFurther) return; // suprimido tras end_call/rechazo

    final cleaned = _normalize(chunk);
    if (cleaned.isEmpty) return;

    // Modo súper simple: mostrar exactamente el último fragmento normalizado (sin heurísticas de crecimiento)
    if (ai.value != cleaned) ai.value = cleaned;

    _aiClearTimer?.cancel();
    _aiClearTimer = Timer(const Duration(seconds: 15), () {
      if (ai.value.isNotEmpty) ai.value = '';
      if (_debug) debugPrint('👁️ [SUB] cleared (timeout)');
    });
  }

  /// Actualiza subtítulo del usuario con filtrado de frases prohibidas.
  void handleUserTranscription(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return;

    final lower = raw.toLowerCase();
    const blocked = <String>{
      'subtítulos realizados por la comunidad de amara.org',
      'subtitulos realizados por la comunidad de amara.org',
    };
    final blockedRegex = RegExp(
      r'subt[íi]tulos\s+realizados\s+por\s+la\s+comunidad\s+de\s+amara\.org',
      caseSensitive: false,
    );
    if (blocked.contains(lower) || blockedRegex.hasMatch(raw) || lower.startsWith('🎤 user transcription received')) {
      if (_debug) debugPrint('👁️ [SUB-UI][user] suprimido watermark/artefacto: "$raw"');
      return;
    }

    user.value = raw;
    _userClearTimer?.cancel();
    _userClearTimer = Timer(const Duration(seconds: 8), () {
      if (user.value.isNotEmpty) user.value = '';
    });
  }
}
