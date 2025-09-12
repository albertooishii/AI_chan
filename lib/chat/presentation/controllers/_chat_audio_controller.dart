import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';

/// 🔊 **Chat Audio Controller** - DDD Specialized Controller
///
/// Handles all audio-related functionality for chat:
/// - Recording audio messages
/// - Playing audio messages
/// - TTS generation
/// - Audio state management
///
/// **DDD Principles:**
/// - Single Responsibility: Only audio operations
/// - Delegation: All logic delegated to ChatApplicationService
class ChatAudioController extends ChangeNotifier {
  ChatAudioController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Audio UI state getters (delegated to service)
  bool get isRecording => _chatService.isRecording;
  List<int> get currentWaveform => _chatService.currentWaveform;
  String get liveTranscript => _chatService.liveTranscript;
  Duration get recordingElapsed => _chatService.recordingElapsed;
  Duration get playingPosition => _chatService.playingPosition;
  Duration get playingDuration => _chatService.playingDuration;
  bool get isSendingAudio => _chatService.isSendingAudio;
  bool get isUploadingUserAudio => _chatService.isUploadingUserAudio;

  // Direct access to audio service for UI components
  IAudioChatService get audioService => _chatService.audioService;

  /// Start recording audio message
  Future<void> startRecording() async {
    try {
      await _chatService.startRecording();
      notifyListeners(); // Notificar cambios en el estado de grabación
    } on Exception catch (e) {
      debugPrint('Error in startRecording: $e');
      rethrow;
    }
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    try {
      await _chatService.cancelRecording();
      notifyListeners(); // Notificar cambios en el estado de grabación
    } on Exception catch (e) {
      debugPrint('Error in cancelRecording: $e');
      rethrow;
    }
  }

  /// Stop recording and send as message
  Future<void> stopAndSendRecording({final String? model}) async {
    try {
      final path = await _chatService
          .stopAndSendRecording(); // Model selection is now automatic
      if (path != null) {
        notifyListeners(); // Notificar que se envió un mensaje de audio
      }
    } on Exception catch (e) {
      debugPrint('Error in stopAndSendRecording: $e');
      rethrow;
    }
  }

  /// Toggle audio playback for a message
  Future<void> togglePlayAudio(final Message msg) async {
    try {
      await _chatService.togglePlayAudio(msg);
      notifyListeners(); // Notificar cambios en la reproducción de audio
    } on Exception catch (e) {
      debugPrint('Error in togglePlayAudio: $e');
      rethrow;
    }
  }

  /// Generate TTS audio for a message
  Future<void> generateTtsForMessage(
    final Message msg, {
    final String voice = '', // Dinámico del provider configurado
  }) async {
    try {
      await _chatService.generateTtsForMessage(msg);
      notifyListeners(); // Notificar cambios en el mensaje (se agregó audio)
    } on Exception catch (e) {
      debugPrint('Error in generateTtsForMessage: $e');
      rethrow;
    }
  }

  /// Check if a message is currently playing
  bool isPlaying(final Message msg) => _chatService.isPlaying(msg);

  @override
  void dispose() {
    // Audio service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
