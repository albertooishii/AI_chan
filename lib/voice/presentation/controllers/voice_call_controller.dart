import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/voice/domain/interfaces/i_tone_service.dart';
// REMOVED: Direct infrastructure imports - using shared.dart instead

/// 🎯 Controller para llamadas de voz completas con IA
/// Integra conversaciones reales usando TTS, STT y respuestas de IA
class VoiceCallController extends ChangeNotifier {
  VoiceCallController({
    final IVoiceConversationService? voiceConversation,
    final IToneService? toneService,
  }) {
    _voiceConversation = voiceConversation ?? getVoiceConversationService();
    _automaticListening = CentralizedListeningService(HybridSttService());
    _toneService = toneService ?? getToneService();
    _setupConversationListener();
  }

  late final IVoiceConversationService _voiceConversation;
  late final CentralizedListeningService _automaticListening;
  late final IToneService _toneService;
  StreamSubscription<ConversationState>? _stateSubscription;

  // Configuración de modo
  bool _useHybridMode = true; // Por defecto híbrido, opción para realtime

  // Estado de la llamada
  bool _isInCall = false;
  bool _isMuted = false;

  bool _isDisposed = false;
  double _volume = 0.7;
  ConversationState _conversationState = ConversationState.idle;
  String _lastResponse = '';
  String _errorMessage = '';

  // Para filtrar eco
  String _lastAiResponse = '';

  // Getters para la UI
  bool get isInCall => _isInCall;
  bool get isMuted => _isMuted;
  bool get isListening => _automaticListening.isListening;

  bool get useHybridMode => _useHybridMode;
  double get volume => _volume;
  ConversationState get conversationState => _conversationState;
  String get lastResponse => _lastResponse;
  String get errorMessage => _errorMessage;

  String get statusText {
    switch (_conversationState) {
      case ConversationState.idle:
        return _isInCall
            ? '🟢 Listo para hablar'
            : '� Presiona para llamar a AI-chan';
      case ConversationState.listening:
        return '🎤 Escuchando...';
      case ConversationState.processing:
        return '🤔 AI-chan está pensando...';
      case ConversationState.speaking:
        return '🗣️ AI-chan está hablando';
      case ConversationState.error:
        return '❌ Error: $_errorMessage';
    }
  }

  /// Configurar listener para cambios de estado de conversación
  void _setupConversationListener() {
    _stateSubscription = _voiceConversation.stateStream.listen(
      (final state) {
        _conversationState = state;

        // 🎯 Mapear estados de voice a shared y actualizar servicio automático
        ConversationState sharedState;
        switch (state) {
          case ConversationState.idle:
            sharedState = ConversationState.idle;
            break;
          case ConversationState.listening:
            sharedState = ConversationState.listening;
            break;
          case ConversationState.processing:
            sharedState = ConversationState.processing;
            break;
          case ConversationState.speaking:
            sharedState = ConversationState.speaking;
            break;
          case ConversationState.error:
            sharedState = ConversationState.error;
            break;
        }

        // Actualizar servicio automático con el nuevo estado
        _automaticListening.updateConversationState(sharedState);

        notifyListeners();
      },
      onError: (final error) {
        _errorMessage = error.toString();
        _conversationState = ConversationState.error;
        _automaticListening.updateConversationState(ConversationState.error);
        notifyListeners();
      },
    );
  }

  /// 📞 Iniciar llamada de voz real con IA
  Future<void> startCall() async {
    try {
      _errorMessage = '';
      _isInCall = true;
      notifyListeners();

      // 🎵 Reproducir tono de llamada 3 veces antes de conectar
      await _toneService.playRingtone();

      // Inicializar sistema de escucha automática
      if (_useHybridMode) {
        await _automaticListening.initialize(
          onTextDetected: (final text) async {
            debugPrint(
              '🎯 VoiceCallController: Texto detectado automáticamente: "$text"',
            );

            // 🔇 Filtrar eco: no procesar si es muy similar a la última respuesta de AI
            if (_isEchoOfAiResponse(text)) {
              debugPrint('🔇 VoiceCallController: Filtrado eco de AI: "$text"');
              return;
            }

            await processTextInput(text);
          },
        );
        _automaticListening.setEnabled(true);
      }

      // Iniciar conversación de voz con AI-chan
      await _voiceConversation.startConversation(
        voiceSettings: VoiceSettings(
          voiceId: '', // Dinámico del provider configurado
          volume: _volume,
          language: 'es',
        ),
      );

      // Iniciar simulación de amplitud del micrófono
      CentralizedMicrophoneAmplitudeService.instance.startListening();

      debugPrint(
        '🎯 VoiceCallController: Llamada de voz iniciada con IA (${_useHybridMode ? 'Híbrido' : 'Realtime'})',
      );
    } on Exception catch (e) {
      _errorMessage = 'Error iniciando llamada: $e';
      _conversationState = ConversationState.error;
      _isInCall = false;

      // 📵 Reproducir tono de error
      await _toneService.playHangupTone();

      notifyListeners();
      debugPrint('❌ Error iniciando llamada: $e');
    }
  }

  /// ❌ Terminar llamada
  Future<void> endCall() async {
    if (!_isInCall) return;

    try {
      debugPrint('🎯 VoiceCallController: Terminando llamada');

      // Detener escucha automática
      _automaticListening.setEnabled(false);

      _isInCall = false;

      // Finalizar conversación
      await _voiceConversation.endConversation();

      // Parar monitoreo de amplitud
      CentralizedMicrophoneAmplitudeService.instance.stopListening();

      // 📵 Reproducir tono de colgado
      await _toneService.playHangupTone();

      // Solo notificar si no hemos sido disposed
      if (!_isDisposed) {
        notifyListeners();
      }

      debugPrint('🎯 VoiceCallController: Llamada terminada');
    } on Exception catch (e) {
      _errorMessage = 'Error terminando llamada: $e';

      // 📵 Reproducir tono de error también
      await _toneService.playHangupTone();

      if (!_isDisposed) {
        notifyListeners();
      }
      debugPrint('❌ Error terminando llamada: $e');
    }
  }

  /// 🔄 Cambiar entre modo híbrido y realtime
  void toggleVoiceMode() {
    _useHybridMode = !_useHybridMode;
    notifyListeners();
    debugPrint(
      '� VoiceCallController: Modo ${_useHybridMode ? 'Híbrido' : 'Realtime'} activado',
    );
  }

  /// �🎤 Inicializar sistema híbrido

  Future<void> processVoiceInput(
    final List<int> audioData,
    final String format,
  ) async {
    if (!_isInCall || _isMuted) return;

    try {
      final turn = await _voiceConversation.processVoiceInput(
        audioData: audioData,
        format: format,
      );

      _lastResponse = turn.content;
      notifyListeners();

      debugPrint('🎯 VoiceCallController: Procesando entrada de voz');
    } on Exception catch (e) {
      _errorMessage = 'Error procesando voz: $e';
      _conversationState = ConversationState.error;
      notifyListeners();
      debugPrint('❌ Error procesando voz: $e');
    }
  }

  /// 📝 Procesar entrada de texto (para testing)
  Future<void> processTextInput(final String text) async {
    if (!_isInCall) return;

    try {
      final turn = await _voiceConversation.processTextInput(text: text);

      _lastResponse = turn.content;
      _lastAiResponse = turn.content; // 🔇 Guardar para filtro de eco
      notifyListeners();

      debugPrint('🎯 VoiceCallController: Procesando texto: $text');
    } on Exception catch (e) {
      _errorMessage = 'Error procesando texto: $e';
      _conversationState = ConversationState.error;
      notifyListeners();
      debugPrint('❌ Error procesando texto: $e');
    }
  }

  /// 🔇 Detecta si el texto detectado es eco de la última respuesta de AI
  bool _isEchoOfAiResponse(final String detectedText) {
    if (_lastAiResponse.isEmpty) return false;

    // Normalizar textos para comparación
    final normalizedDetected = detectedText.toLowerCase().trim();
    final normalizedAi = _lastAiResponse.toLowerCase().trim();

    // Si el texto detectado está contenido en la respuesta de AI (70% o más)
    final similarity = _calculateTextSimilarity(
      normalizedDetected,
      normalizedAi,
    );

    debugPrint(
      '🔍 Echo check: "$normalizedDetected" vs "$normalizedAi" - similarity: ${similarity.toStringAsFixed(2)}',
    );

    return similarity > 0.7; // 70% de similitud indica probable eco
  }

  /// 📊 Calcula similitud entre dos textos (algoritmo simple)
  double _calculateTextSimilarity(final String text1, final String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    // Comprobar si uno está contenido en el otro
    if (text2.contains(text1) || text1.contains(text2)) {
      return text1.length / text2.length.clamp(1, double.infinity);
    }

    // Algoritmo de palabras comunes simple
    final words1 = text1.split(' ').where((final w) => w.length > 2).toSet();
    final words2 = text2.split(' ').where((final w) => w.length > 2).toSet();

    if (words1.isEmpty || words2.isEmpty) return 0.0;

    final commonWords = words1.intersection(words2).length;
    final totalWords = words1.union(words2).length;

    return commonWords / totalWords;
  }

  /// 🔇 Toggle mute/unmute
  void toggleMute() {
    _isMuted = !_isMuted;

    // Manejar amplitud del micrófono según estado de mute
    if (_isInCall) {
      if (_isMuted) {
        CentralizedMicrophoneAmplitudeService.instance.stopListening();
      } else {
        CentralizedMicrophoneAmplitudeService.instance.startListening();
      }
    }

    notifyListeners();
    debugPrint('🎯 VoiceCallController: Mute ${_isMuted ? 'ON' : 'OFF'}');
  }

  /// 🔊 Ajustar volumen
  void setVolume(final double newVolume) {
    _volume = newVolume.clamp(0.0, 1.0);

    // Actualizar configuración de voz si está en llamada
    if (_isInCall) {
      _voiceConversation.updateVoiceSettings(
        VoiceSettings(voiceId: '', volume: _volume, language: 'es'),
      ); // Dinámico
    }

    notifyListeners();
    debugPrint('🎯 VoiceCallController: Volumen = ${(_volume * 100).round()}%');
  }

  /// ❌ Limpiar error
  void clearError() {
    _errorMessage = '';
    if (_conversationState == ConversationState.error) {
      _conversationState = ConversationState.idle;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    // Marcar como disposed
    _isDisposed = true;

    // Limpiar recursos
    _stateSubscription?.cancel();
    if (_isInCall) {
      endCall();
    }
    super.dispose();
  }
}
