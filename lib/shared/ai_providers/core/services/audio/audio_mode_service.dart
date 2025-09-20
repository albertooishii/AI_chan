import 'dart:async';
import 'package:ai_chan/shared/ai_providers/core/models/audio_mode.dart';
import 'package:ai_chan/shared.dart';

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

  /// Obtener todos los contextos disponibles
  static Future<Map<String, AudioMode>> getAllContextModes() async {
    await initialize();
    return Map.unmodifiable(_contextModes);
  }
}
