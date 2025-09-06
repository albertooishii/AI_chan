import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/utils/string_utils.dart';

/// Controlador de subtítulos para streaming en tiempo real.
/// Diseñado para mostrar subtítulos inmediatamente según llegan los chunks de IA,
/// sin esperar a que termine el audio completo.
class StreamingSubtitleController {
  StreamingSubtitleController({final bool debug = false}) : _debug = debug;

  bool _debug;
  bool get debug => _debug;
  void setDebug(final bool value) => _debug = value;

  final ValueNotifier<String> ai = ValueNotifier<String>('');
  final ValueNotifier<String> user = ValueNotifier<String>('');

  Timer? _aiClearTimer;
  Timer? _userClearTimer;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _aiClearTimer?.cancel();
    _userClearTimer?.cancel();
    ai.dispose();
    user.dispose();
  }

  void clearAll() {
    if (_disposed) return;
    _aiClearTimer?.cancel();
    _userClearTimer?.cancel();
    if (ai.value.isNotEmpty) ai.value = '';
    if (user.value.isNotEmpty) user.value = '';
  }

  /// Maneja chunks de IA en tiempo real - muestra inmediatamente
  void handleAiChunk(
    final String chunk, {
    required final bool audioStarted,
    required final bool suppressFurther,
  }) {
    if (_disposed) return;

    if (_debug) {
      debugPrint('🎬 [StreamingSubtitle] AI chunk: "$chunk"');
    }

    // Ignorar sentinel de reveal
    if (chunk == '__REVEAL__') return;

    // No mostrar antes de que empiece el audio
    if (!audioStarted) return;

    // Suprimir si se detectó end_call o rechazo
    if (suppressFurther) return;

    final cleaned = cleanSubtitleText(chunk);
    if (cleaned.isEmpty) return;

    // Mostrar inmediatamente el chunk limpio
    ai.value = cleaned;

    // Auto-clear después de 15 segundos
    _aiClearTimer?.cancel();
    _aiClearTimer = Timer(const Duration(seconds: 15), () {
      if (!_disposed && ai.value.isNotEmpty) {
        ai.value = '';
        if (_debug) debugPrint('🎬 [StreamingSubtitle] AI cleared (timeout)');
      }
    });
  }

  /// Maneja transcripciones del usuario
  void handleUserTranscription(final String text) {
    if (_disposed) return;

    final raw = text.trim();
    if (raw.isEmpty) return;

    // Filtrar frases prohibidas y artefactos comunes
    final lower = raw.toLowerCase();
    const blocked = <String>{
      'subtítulos realizados por la comunidad de amara.org',
      'subtitulos realizados por la comunidad de amara.org',
    };

    final blockedRegex = RegExp(
      r'subt[íi]tulos\s+realizados\s+por\s+la\s+comunidad\s+de\s+amara\.org',
      caseSensitive: false,
    );

    if (blocked.contains(lower) ||
        blockedRegex.hasMatch(raw) ||
        lower.startsWith('🎤 user transcription received')) {
      if (_debug) {
        debugPrint(
          '🎬 [StreamingSubtitle] User transcription filtered: "$raw"',
        );
      }
      return;
    }

    user.value = raw;

    if (_debug) {
      debugPrint('🎬 [StreamingSubtitle] User: "$raw"');
    }

    // Auto-clear después de 8 segundos
    _userClearTimer?.cancel();
    _userClearTimer = Timer(const Duration(seconds: 8), () {
      if (!_disposed && user.value.isNotEmpty) {
        user.value = '';
      }
    });
  }

  /// Limpia texto de IA manualmente
  void clearAi() {
    if (_disposed) return;
    _aiClearTimer?.cancel();
    if (ai.value.isNotEmpty) ai.value = '';
  }

  /// Limpia texto de usuario manualmente
  void clearUser() {
    if (_disposed) return;
    _userClearTimer?.cancel();
    if (user.value.isNotEmpty) user.value = '';
  }

  /// Muestra texto de IA instantáneamente (para casos especiales)
  void showAiTextInstant(final String text) {
    if (_disposed) return;

    final cleaned = cleanSubtitleText(text);
    if (cleaned.isEmpty) return;

    ai.value = cleaned;

    if (_debug) {
      debugPrint('🎬 [StreamingSubtitle] AI instant: "$cleaned"');
    }

    _aiClearTimer?.cancel();
    _aiClearTimer = Timer(const Duration(seconds: 15), () {
      if (!_disposed && ai.value.isNotEmpty) {
        ai.value = '';
      }
    });
  }
}
