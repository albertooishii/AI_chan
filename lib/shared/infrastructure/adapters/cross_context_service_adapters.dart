import '../../domain/interfaces/cross_context_interfaces.dart';
import '../../ai_providers/core/services/audio/centralized_tts_service.dart';
import '../../ai_providers/core/services/audio/centralized_stt_service.dart';
import '../../ai_providers/core/models/audio/voice_settings.dart';
import 'dart:async';

/// 🏗️ Infrastructure Adapter for Text-to-Speech Service
/// Adapts CentralizedTtsService to the domain interface
/// Following Port-Adapter pattern to maintain decoupling
class TextToSpeechServiceAdapter implements ITextToSpeechService {
  const TextToSpeechServiceAdapter();

  CentralizedTtsService get _service => CentralizedTtsService.instance;

  @override
  Future<void> speak(
    final String text, {
    final String? language,
    final double? rate,
    final double? pitch,
  }) async {
    // Adapt to CentralizedTtsService interface
    final settings = VoiceSettings(
      voiceId: 'default', // Could be enhanced to map language to voice
      speed: rate ?? 1.0,
      pitch: pitch ?? 1.0,
      language: language ?? 'en-US',
    );

    await _service.synthesize(text: text, settings: settings);
  }

  @override
  Future<void> stop() async {
    // CentralizedTtsService doesn't have stop method yet
    // This is a basic implementation that satisfies the interface
    // Could be enhanced when stop functionality is added to the service
  }

  @override
  Future<bool> isSpeaking() async {
    // CentralizedTtsService doesn't have isSpeaking method yet
    // This is a basic implementation that satisfies the interface
    // Could be enhanced when speaking status is added to the service
    return false;
  }
}

/// 🏗️ Infrastructure Adapter for Speech-to-Text Service
/// Adapts CentralizedSttService to the domain interface
/// Following Port-Adapter pattern to maintain decoupling
class SpeechToTextServiceAdapter implements ISpeechToTextService {
  SpeechToTextServiceAdapter();

  CentralizedSttService get _service => CentralizedSttService.instance;
  StreamController<String>? _textController;

  @override
  Future<void> startListening({final String? language}) async {
    _textController?.close();
    _textController = StreamController<String>();

    // Adapt CentralizedSttService streaming to our interface
    final recognitionStream = _service.startListening(
      language: language ?? 'en-US',
    );

    recognitionStream.listen((final result) {
      if (result.isFinal) {
        _textController?.add(result.text);
      }
    });
  }

  @override
  Future<void> stopListening() async {
    await _service.stopListening();
    _textController?.close();
    _textController = null;
  }

  @override
  Stream<String> get onTextReceived =>
      _textController?.stream ?? const Stream.empty();

  @override
  Future<bool> isAvailable() async {
    return _service.isAvailable();
  }
}

/// 🏗️ Infrastructure Adapter for Chat Integration Service
/// Provides a basic implementation that delegates to the chat context
/// Following Port-Adapter pattern to maintain decoupling
class ChatIntegrationServiceAdapter implements IChatIntegrationService {
  const ChatIntegrationServiceAdapter();

  @override
  Future<void> sendMessageFromCall(
    final String message,
    final Map<String, dynamic>? metadata,
  ) async {
    // Basic implementation - could be enhanced to use proper message bus
    // For now, this adapter provides the interface but the actual implementation
    // would depend on the specific chat system integration
    // This maintains the architectural boundary while allowing future implementation
  }

  @override
  Future<bool> isChatAvailable() async {
    // Basic implementation - assumes chat is always available
    // Could be enhanced to check actual chat service status
    return true;
  }

  @override
  Future<void> notifyCallEvent(
    final String eventType,
    final Map<String, dynamic> data,
  ) async {
    // Basic implementation - could be enhanced to use proper event bus
    // This maintains the architectural boundary while allowing future implementation
  }
}

/// 🏗️ Infrastructure Adapter for Call Integration Service
/// Provides a basic implementation that delegates to the call context
/// Following Port-Adapter pattern to maintain decoupling
class CallIntegrationServiceAdapter implements ICallIntegrationService {
  const CallIntegrationServiceAdapter();

  @override
  Future<void> startCallFromChat() async {
    // Basic implementation - could be enhanced to use proper call service
    // This maintains the architectural boundary while allowing future implementation
  }

  @override
  Future<void> endCallFromChat() async {
    // Basic implementation - could be enhanced to use proper call service
    // This maintains the architectural boundary while allowing future implementation
  }

  @override
  Future<bool> isCallActive() async {
    // Basic implementation - assumes no call is active
    // Could be enhanced to check actual call service status
    return false;
  }

  @override
  Future<void> sendMessageToCall(final String message) async {
    // Basic implementation - could be enhanced to use proper message bus
    // This maintains the architectural boundary while allowing future implementation
  }
}
