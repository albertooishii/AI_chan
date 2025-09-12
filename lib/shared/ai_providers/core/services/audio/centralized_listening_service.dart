import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../interfaces/audio/i_audio_playback_service.dart';
import '../audio/centralized_audio_playback_service.dart';
import '../../../../services/hybrid_stt_service.dart';
import '../../../../domain/enums/conversation_state.dart';

/// 🎯 Servicio centralizado para escucha automática inteligente
/// Coordina TTS, STT y timing para conversaciones naturales
class CentralizedListeningService extends ChangeNotifier {
  CentralizedListeningService(this._hybridStt);

  final HybridSttService _hybridStt;
  final IAudioPlaybackService _audioService =
      CentralizedAudioPlaybackService.instance;

  bool _isListening = false;
  bool _isEnabled = false;
  ConversationState _currentState = ConversationState.idle;
  String? _errorMessage;

  // Callback para procesar texto detectado
  void Function(String text)? _onTextDetected;

  // Subscripciones para coordinar audio y listening
  StreamSubscription<void>? _audioCompletionSubscription;
  Timer? _fallbackTimer;
  Timer? _postAudioDelayTimer;

  // Getters
  bool get isListening => _isListening;
  bool get isEnabled => _isEnabled;
  ConversationState get currentState => _currentState;
  String? get errorMessage => _errorMessage;

  /// Inicializa el servicio de escucha automática
  Future<bool> initialize({
    required final void Function(String text) onTextDetected,
  }) async {
    _onTextDetected = onTextDetected;

    final initialized = await _hybridStt.initialize(
      onStatus: _handleSttStatus,
      onError: _handleSttError,
    );

    if (initialized) {
      debugPrint('🎯 CentralizedListening: Inicializado exitosamente');
    } else {
      debugPrint('❌ CentralizedListening: Error en inicialización');
    }

    return initialized;
  }

  /// Habilita/deshabilita la escucha automática
  void setEnabled(final bool enabled) {
    _isEnabled = enabled;
    notifyListeners();

    if (!enabled) {
      if (_isListening) {
        stopListening();
      }
      // Cancelar todos los timers y subscripciones cuando se deshabilita
      _cleanup();
    }

    debugPrint(
      '🎯 CentralizedListening: ${enabled ? "Habilitado" : "Deshabilitado"}',
    );
  }

  /// Actualiza el estado de conversación para controlar la escucha
  void updateConversationState(final ConversationState state) {
    final previousState = _currentState;
    _currentState = state;
    notifyListeners();

    debugPrint('🎯 CentralizedListening: Estado $previousState → $state');

    if (!_isEnabled) return;

    switch (state) {
      case ConversationState.speaking:
        // 🔇 Parar escucha cuando AI habla (evitar eco)
        if (_isListening) {
          stopListening();
          debugPrint(
            '🎯 CentralizedListening: AI hablando - deteniendo escucha',
          );
        }

        // 🎵 Configurar listener para cuando termine el audio TTS
        _setupAudioCompletionListener();
        break;

      case ConversationState.listening:
        // 🎤 Solo iniciar escucha si venimos de idle (no de speaking)
        if (previousState == ConversationState.idle && !_isListening) {
          startListening();
        }
        // Si venimos de speaking, esperamos la notificación de audio completion
        break;

      case ConversationState.processing:
        // 🔇 Parar escucha durante procesamiento
        if (_isListening) {
          stopListening();
          debugPrint(
            '🎯 CentralizedListening: Procesando - deteniendo escucha',
          );
        }
        break;

      default:
        break;
    }
  }

  /// Configura listener para escuchar cuando termine el audio TTS
  void _setupAudioCompletionListener() {
    // Cancelar listener anterior si existe
    _cleanup();

    // Configurar listener para cuando termine el audio
    _audioCompletionSubscription = _audioService.completionStream.listen((_) {
      debugPrint(
        '🎯 CentralizedListening: TTS completado - programando inicio de escucha',
      );

      if (_currentState == ConversationState.listening &&
          _isEnabled &&
          !_isListening) {
        // Pequeña pausa para asegurar que el audio está completamente terminado
        // y permitir que el eco se disipar
        _postAudioDelayTimer = Timer(const Duration(milliseconds: 300), () {
          if (_currentState == ConversationState.listening &&
              _isEnabled &&
              !_isListening) {
            debugPrint(
              '🎯 CentralizedListening: Iniciando escucha después del TTS',
            );
            startListening();
          }
        });
      }
    });

    // Timer de fallback en caso de que no se reciba la notificación de completion
    _fallbackTimer = Timer(const Duration(seconds: 8), () {
      if (_currentState == ConversationState.listening &&
          _isEnabled &&
          !_isListening) {
        debugPrint(
          '🎯 CentralizedListening: Fallback timer - iniciando escucha',
        );
        startListening();
      }
    });
  }

  /// Inicia la escucha automática
  void startListening() {
    if (!_isEnabled || _isListening || _onTextDetected == null) return;

    _hybridStt.listen(
      onResult: (final text) {
        debugPrint('🎯 CentralizedListening: Texto detectado: "$text"');

        if (text.trim().isNotEmpty) {
          _isListening = false;
          notifyListeners();

          // Notificar texto detectado
          _onTextDetected?.call(text);
        }
      },
      timeout: const Duration(seconds: 10), // Timeout para conversación natural
    );

    _isListening = true;
    _errorMessage = null;
    notifyListeners();

    debugPrint('🎯 CentralizedListening: Escucha iniciada');
  }

  /// Detiene la escucha automática
  void stopListening() {
    if (!_isListening) return;

    _hybridStt.stop();
    _isListening = false;
    notifyListeners();

    debugPrint('🎯 CentralizedListening: Escucha detenida');
  }

  /// Maneja cambios de estado del STT
  void _handleSttStatus(final String status) {
    debugPrint('🎯 CentralizedListening STT Status: $status');
  }

  /// Maneja errores del STT
  void _handleSttError(final String error) {
    _errorMessage = error;
    _isListening = false;
    notifyListeners();

    debugPrint('❌ CentralizedListening STT Error: $error');

    // Reintentar después de un error si está habilitado
    if (_isEnabled && _currentState == ConversationState.listening) {
      Timer(const Duration(seconds: 2), () {
        if (_isEnabled && _currentState == ConversationState.listening) {
          startListening();
        }
      });
    }
  }

  /// Limpiar timers y subscripciones
  void _cleanup() {
    _audioCompletionSubscription?.cancel();
    _audioCompletionSubscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _postAudioDelayTimer?.cancel();
    _postAudioDelayTimer = null;
  }

  @override
  void dispose() {
    stopListening();
    _cleanup();
    _hybridStt.dispose();
    super.dispose();
  }
}
