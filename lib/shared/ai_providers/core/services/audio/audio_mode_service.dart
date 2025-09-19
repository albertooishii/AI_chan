import 'dart:async';
import 'package:ai_chan/shared/ai_providers/core/models/audio_mode.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/ai_providers/core/services/audio/centralized_tts_service.dart';

/// Servicio para gestionar modos de audio de forma desacoplada
/// Permite elegir entre híbrido y realtime según el contexto
class AudioModeService {
  AudioModeService._();

  /// Cache de configuraciones por contexto
  static final Map<String, AudioMode> _contextModes = {};
  static bool _initialized = false;

  /// Inicializar configuraciones desde YAML o defaults
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Por ahora usar defaults hasta que se implemente contextAudioModes en YAML
      _contextModes.clear();

      // Defaults por contexto
      _contextModes.addAll({
        'onboarding': AudioMode.hybrid, // Siempre híbrido para onboarding
        'voice_calls': AudioMode.realtime, // Realtime para llamadas de voz
        'chat': AudioMode.hybrid, // Híbrido para chat normal
        'default': AudioMode.hybrid, // Fallback general
      });

      _initialized = true;
      Log.d('[AudioModeService] Inicializado con contextos: $_contextModes');
    } on Exception catch (e) {
      Log.e('[AudioModeService] Error inicializando: $e');
      // Fallback a defaults seguros
      _contextModes.addAll({
        'onboarding': AudioMode.hybrid,
        'voice_calls': AudioMode.hybrid, // Fallback a híbrido si falla
        'chat': AudioMode.hybrid,
        'default': AudioMode.hybrid,
      });
      _initialized = true;
    }
  }

  /// Obtener modo configurado para un contexto
  static Future<AudioMode> getModeForContext(final String context) async {
    await initialize();
    return _contextModes[context] ??
        _contextModes['default'] ??
        AudioMode.hybrid;
  }

  /// Crear servicio TTS para un contexto específico
  static Future<ITtsService> createTtsForContext(final String context) async {
    final mode = await getModeForContext(context);

    Log.d(
      '[AudioModeService] Creando TTS para contexto: $context (modo: ${mode.identifier})',
    );

    // Por ahora, tanto híbrido como realtime usan el mismo servicio TTS centralizado
    // La diferencia estará en cómo se maneja la conversación completa
    return CentralizedTtsService.instance;
  }

  /// Cambiar modo para un contexto (runtime)
  static Future<void> setModeForContext(
    final String context,
    final AudioMode mode,
  ) async {
    await initialize();
    _contextModes[context] = mode;
    Log.d('[AudioModeService] Modo cambiado para $context: ${mode.identifier}');
  }

  /// Obtener todos los contextos disponibles
  static Future<Map<String, AudioMode>> getAllContextModes() async {
    await initialize();
    return Map.unmodifiable(_contextModes);
  }

  /// Verificar si un modo está disponible
  static Future<bool> isModeAvailable(final AudioMode mode) async {
    switch (mode) {
      case AudioMode.hybrid:
        // Híbrido siempre disponible (usa TTS + STT + texto)
        return true;

      case AudioMode.realtime:
        // Realtime disponible si hay providers que lo soporten
        try {
          final models = await RealtimeService.getAvailableRealtimeModels();
          return models.isNotEmpty;
        } on Exception catch (e) {
          Log.w('[AudioModeService] Error verificando realtime: $e');
          return false;
        }
    }
  }

  /// Obtener descripción del modo actual para un contexto
  static Future<String> getModeDescriptionForContext(
    final String context,
  ) async {
    final mode = await getModeForContext(context);
    return '${mode.displayName}: ${mode.description}';
  }

  /// Verificar si se puede cambiar a realtime para un contexto
  static Future<bool> canSwitchToRealtime(final String context) async {
    return await isModeAvailable(AudioMode.realtime);
  }

  /// Cambiar a modo alternativo para un contexto
  static Future<AudioMode> toggleModeForContext(final String context) async {
    final currentMode = await getModeForContext(context);
    final newMode = currentMode == AudioMode.hybrid
        ? AudioMode.realtime
        : AudioMode.hybrid;

    // Verificar si el nuevo modo está disponible
    if (await isModeAvailable(newMode)) {
      await setModeForContext(context, newMode);
      Log.d(
        '[AudioModeService] Modo cambiado de ${currentMode.identifier} a ${newMode.identifier} para $context',
      );
      return newMode;
    } else {
      Log.w(
        '[AudioModeService] No se puede cambiar a ${newMode.identifier}, no está disponible',
      );
      return currentMode;
    }
  }
}
