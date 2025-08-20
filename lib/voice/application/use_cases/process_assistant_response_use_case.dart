import 'dart:typed_data';

import 'package:ai_chan/voice/domain/domain.dart';

/// Caso de uso para procesar respuestas del asistente
class ProcessAssistantResponseUseCase {
  final IVoiceCallRepository _repository;

  const ProcessAssistantResponseUseCase(this._repository);

  /// Procesa texto recibido del asistente
  Future<void> executeText({
    required String callId,
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    // Verificar que la llamada existe
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    // Validar texto
    if (text.trim().isEmpty) {
      return; // Ignorar texto vacío
    }

    // Crear mensaje del asistente
    final message = VoiceMessage.assistantText(
      id: _generateMessageId(),
      text: text.trim(),
      metadata: {
        'responseType': 'text',
        'provider': call.provider.name,
        'model': call.model,
        ...?metadata,
      },
    );

    // Guardar mensaje en la llamada
    await _repository.addMessageToCall(callId, message);
  }

  /// Procesa audio recibido del asistente
  Future<void> executeAudio({
    required String callId,
    required List<int> audioData,
    String? audioPath,
    Duration? audioDuration,
    Map<String, dynamic>? metadata,
  }) async {
    // Verificar que la llamada existe
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    // Validar audio
    if (audioData.isEmpty && audioPath == null) {
      return; // Ignorar audio vacío
    }

    // Crear mensaje del asistente
    final message = VoiceMessage.assistantAudio(
      id: _generateMessageId(),
      audioData: audioData.isNotEmpty ? Uint8List.fromList(audioData) : null,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: {
        'responseType': 'audio',
        'provider': call.provider.name,
        'model': call.model,
        'audioSize': audioData.length,
        ...?metadata,
      },
    );

    // Guardar mensaje en la llamada
    await _repository.addMessageToCall(callId, message);
  }

  /// Procesa respuesta mixta (texto + audio) del asistente
  Future<void> executeMixed({
    required String callId,
    required String text,
    required List<int> audioData,
    String? audioPath,
    Duration? audioDuration,
    Map<String, dynamic>? metadata,
  }) async {
    // Verificar que la llamada existe
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    // Validar contenido
    if (text.trim().isEmpty && audioData.isEmpty && audioPath == null) {
      return; // Ignorar respuesta vacía
    }

    // Crear mensaje mixto del asistente
    final message = VoiceMessage.assistantMixed(
      id: _generateMessageId(),
      text: text.trim(),
      audioData: audioData.isNotEmpty ? Uint8List.fromList(audioData) : null,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: {
        'responseType': 'mixed',
        'provider': call.provider.name,
        'model': call.model,
        'audioSize': audioData.length,
        ...?metadata,
      },
    );

    // Guardar mensaje en la llamada
    await _repository.addMessageToCall(callId, message);
  }

  /// Procesa transcripción del usuario
  Future<void> executeUserTranscription({
    required String callId,
    required String transcription,
    Map<String, dynamic>? metadata,
  }) async {
    // Verificar que la llamada existe
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    // Validar transcripción
    if (transcription.trim().isEmpty) {
      return; // Ignorar transcripción vacía
    }

    // Crear mensaje del usuario basado en transcripción
    final message = VoiceMessage.userText(
      id: _generateMessageId(),
      text: transcription.trim(),
      metadata: {
        'inputMethod': 'transcription',
        'provider': call.provider.name,
        ...?metadata,
      },
    );

    // Guardar mensaje en la llamada
    await _repository.addMessageToCall(callId, message);
  }

  /// Genera un ID único para el mensaje
  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }
}
