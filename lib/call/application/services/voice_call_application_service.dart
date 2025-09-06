import 'package:flutter/foundation.dart';
import '../use_cases/start_call_use_case.dart';
import '../use_cases/end_call_use_case.dart';
import '../use_cases/handle_incoming_call_use_case.dart';
import '../use_cases/manage_audio_use_case.dart';
import '../../domain/entities/voice_call_state.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart';

/// 🎯 **Voice Call Application Service** - DDD Coordinator for Call Operations
///
/// Following DDD patterns, acts as **Facade** that coordinates
/// multiple Use Cases and maintains **SRP** (Single Responsibility Principle).
///
/// **Responsibilities:**
/// - Coordinate voice call lifecycle (start, end, manage)
/// - Manage incoming calls and audio flow
/// - Handle real-time audio processing
/// - Maintain consistency between call use cases
///
/// **DDD Principles Implemented:**
/// - ✅ Application Service as coordinator
/// - ✅ Dependency Inversion (depends on abstractions)
/// - ✅ Single Responsibility (only coordination)
/// - ✅ Open/Closed (extensible without modification)
class VoiceCallApplicationService {
  VoiceCallApplicationService({
    required final StartCallUseCase startCallUseCase,
    required final EndCallUseCase endCallUseCase,
    required final HandleIncomingCallUseCase handleIncomingCallUseCase,
    required final ManageAudioUseCase manageAudioUseCase,
  }) : _startCallUseCase = startCallUseCase,
       _endCallUseCase = endCallUseCase,
       _handleIncomingCallUseCase = handleIncomingCallUseCase,
       _manageAudioUseCase = manageAudioUseCase;

  // 🔧 **Use Cases Dependencies** - Core 4 use cases from controller
  final StartCallUseCase _startCallUseCase;
  final EndCallUseCase _endCallUseCase;
  final HandleIncomingCallUseCase _handleIncomingCallUseCase;
  final ManageAudioUseCase _manageAudioUseCase;

  /// 🚀 **Initialize Voice Call System**
  /// Coordinates initialization of all audio and call systems
  Future<VoiceCallInitializationResult> initializeVoiceCall() async {
    try {
      await _manageAudioUseCase.initialize();

      return VoiceCallInitializationResult.success();
    } on Exception catch (e) {
      return VoiceCallInitializationResult.failure('Error initializing voice call: $e');
    }
  }

  /// 📞 **Start Outgoing Call**
  /// Coordinates the complete process of starting an outgoing voice call
  Future<VoiceCallOperationResult> startOutgoingCall({
    required final bool isIncoming,
    required final VoidCallback onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    try {
      await _startCallUseCase.execute(isIncoming: isIncoming, onCallStarted: onCallStarted, onCallEnded: onCallEnded);

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error starting outgoing call: $e');
    }
  }

  /// 📲 **Handle Incoming Call**
  /// Coordinates incoming call management including ringing
  Future<VoiceCallOperationResult> handleIncomingCall() async {
    try {
      await _handleIncomingCallUseCase.startRinging();

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error handling incoming call: $e');
    }
  }

  /// 📞 **Accept Incoming Call**
  /// Coordinates accepting incoming call and stopping ringing
  Future<VoiceCallOperationResult> acceptIncomingCall() async {
    try {
      await _handleIncomingCallUseCase.stopRinging();

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error accepting incoming call: $e');
    }
  }

  /// 📞 **Start Call Internal**
  /// Coordinates the internal call start process with callbacks
  Future<VoiceCallOperationResult> startCallInternal({
    required final bool isIncoming,
    required final VoidCallback onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    try {
      await _startCallUseCase.execute(isIncoming: isIncoming, onCallStarted: onCallStarted, onCallEnded: onCallEnded);

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error starting call internal: $e');
    }
  }

  /// ✋ **Stop Incoming Call Ringing**
  /// Coordinates stopping of incoming call ringing
  Future<VoiceCallOperationResult> stopIncomingCallRinging() async {
    try {
      await _handleIncomingCallUseCase.stopRinging();

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error stopping incoming call ringing: $e');
    }
  }

  /// 🔊 **Manage Audio Settings**
  /// Coordinates audio mute/unmute operations
  void setAudioMuted(final bool muted) {
    _manageAudioUseCase.setMuted(muted);
  }

  /// 📊 **Get Audio Level Stream**
  /// Provides access to audio level monitoring
  Stream<double> get audioLevelStream => _manageAudioUseCase.audioLevelStream;

  /// 🎤 **Check if Audio is Muted**
  /// Returns current mute status
  bool get isMuted => _manageAudioUseCase.isMuted;

  /// 🗑️ **Dispose Audio Resources**
  /// Properly dispose of audio management resources
  void dispose() {
    _manageAudioUseCase.dispose();
  }

  /// 📴 **End Voice Call**
  /// Coordinates the complete process of ending a voice call
  Future<VoiceCallOperationResult> endVoiceCall({
    required final ChatController chatController,
    required final VoiceCallState callState,
  }) async {
    try {
      await _endCallUseCase.execute(chatController: chatController, callState: callState);

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error ending voice call: $e');
    }
  }
}

/// 🎯 **Result Objects for Voice Call Operations**

class VoiceCallInitializationResult {
  factory VoiceCallInitializationResult.success() => const VoiceCallInitializationResult(success: true);

  factory VoiceCallInitializationResult.failure(final String errorMessage) =>
      VoiceCallInitializationResult(success: false, errorMessage: errorMessage);
  const VoiceCallInitializationResult({required this.success, this.errorMessage});

  final bool success;
  final String? errorMessage;
}

class VoiceCallOperationResult {
  factory VoiceCallOperationResult.success() => const VoiceCallOperationResult(success: true);

  factory VoiceCallOperationResult.failure(final String errorMessage) =>
      VoiceCallOperationResult(success: false, errorMessage: errorMessage);
  const VoiceCallOperationResult({required this.success, this.errorMessage});

  final bool success;
  final String? errorMessage;
}

/// 📞 **Voice Call Application Exception**
class VoiceCallApplicationException implements Exception {
  const VoiceCallApplicationException(this.message);

  final String message;

  @override
  String toString() => 'VoiceCallApplicationException: $message';
}
