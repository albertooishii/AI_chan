import 'package:ai_chan/voice/domain/domain.dart';

/// Caso de uso para procesar audio enviado por el usuario
class ProcessUserAudioUseCase {
  final IVoiceCallRepository _repository;
  final IRealtimeVoiceClient _realtimeClient;

  const ProcessUserAudioUseCase(this._repository, this._realtimeClient);

  /// Procesa audio del usuario y lo envía al servicio
  Future<void> execute({
    required String callId,
    required List<int> audioData,
  }) async {
    // Verificar que la llamada existe y está activa
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    if (!_realtimeClient.isConnected) {
      throw StateError('Realtime client is not connected');
    }

    // Enviar audio al cliente realtime
    _realtimeClient.sendAudio(audioData);
  }

  /// Procesa texto del usuario y lo envía al servicio
  Future<void> executeText({
    required String callId,
    required String text,
  }) async {
    // Verificar que la llamada existe y está activa
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    if (!_realtimeClient.isConnected) {
      throw StateError('Realtime client is not connected');
    }

    // Validar texto
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    // Crear mensaje de usuario
    final message = VoiceMessage.userText(
      id: _generateMessageId(),
      text: text.trim(),
      metadata: {'inputMethod': 'text'},
    );

    // Guardar mensaje en la llamada
    await _repository.addMessageToCall(callId, message);

    // Enviar texto al cliente realtime
    _realtimeClient.sendText(text.trim());
  }

  /// Solicita una respuesta del asistente
  Future<void> executeRequestResponse({
    required String callId,
    bool audio = true,
    bool text = true,
  }) async {
    // Verificar que la llamada existe y está activa
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    if (!_realtimeClient.isConnected) {
      throw StateError('Realtime client is not connected');
    }

    // Solicitar respuesta
    _realtimeClient.requestResponse(audio: audio, text: text);
  }

  /// Genera un ID único para el mensaje
  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }
}
