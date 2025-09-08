import 'dart:async';
import '../use_cases/start_call_use_case.dart';
import '../use_cases/end_call_use_case.dart';
import '../use_cases/handle_incoming_call_use_case.dart';
import '../use_cases/manage_audio_use_case.dart';
import '../../domain/entities/voice_call_state.dart';
import 'package:ai_chan/core/domain/interfaces/i_call_to_chat_communication_service.dart'; // ✅ Bounded Context Abstraction

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
    required final ICallToChatCommunicationService
    chatCommunicationService, // ✅ Bounded Context Abstraction
  }) : _startCallUseCase = startCallUseCase,
       _endCallUseCase = endCallUseCase,
       _handleIncomingCallUseCase = handleIncomingCallUseCase,
       _manageAudioUseCase = manageAudioUseCase,
       _chatCommunicationService =
           chatCommunicationService; // ✅ Bounded Context Abstraction

  // 🔧 **Use Cases Dependencies** - Core 4 use cases from controller
  final StartCallUseCase _startCallUseCase;
  final EndCallUseCase _endCallUseCase;
  final HandleIncomingCallUseCase _handleIncomingCallUseCase;
  final ManageAudioUseCase _manageAudioUseCase;
  // ignore: unused_field
  final ICallToChatCommunicationService
  _chatCommunicationService; // ✅ Bounded Context Abstraction

  /// 🚀 **Initialize Voice Call System**
  /// Coordinates initialization of all audio and call systems
  Future<VoiceCallInitializationResult> initializeVoiceCall() async {
    try {
      await _manageAudioUseCase.initialize();

      return VoiceCallInitializationResult.success();
    } on Exception catch (e) {
      return VoiceCallInitializationResult.failure(
        'Error initializing voice call: $e',
      );
    }
  }

  /// 📞 **Start Outgoing Call**
  /// Coordinates the complete process of starting an outgoing voice call
  Future<VoiceCallOperationResult> startOutgoingCall({
    required final bool isIncoming,
    required final void Function() onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    return _executeStartCall(
      isIncoming: isIncoming,
      onCallStarted: onCallStarted,
      onCallEnded: onCallEnded,
      errorMessage: 'Error starting outgoing call',
    );
  }

  /// 📲 **Handle Incoming Call**
  /// Coordinates incoming call management including ringing
  Future<VoiceCallOperationResult> handleIncomingCall() async {
    try {
      await _handleIncomingCallUseCase.startRinging();

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure(
        'Error handling incoming call: $e',
      );
    }
  }

  /// 📞 **Accept Incoming Call**
  /// Coordinates accepting incoming call and stopping ringing
  Future<VoiceCallOperationResult> acceptIncomingCall() async {
    try {
      await _handleIncomingCallUseCase.stopRinging();

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure(
        'Error accepting incoming call: $e',
      );
    }
  }

  /// 📞 **Start Call Internal**
  /// Coordinates the internal call start process with callbacks
  Future<VoiceCallOperationResult> startCallInternal({
    required final bool isIncoming,
    required final void Function() onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    return _executeStartCall(
      isIncoming: isIncoming,
      onCallStarted: onCallStarted,
      onCallEnded: onCallEnded,
      errorMessage: 'Error starting call internal',
    );
  }

  /// ✋ **Stop Incoming Call Ringing**
  /// Coordinates stopping of incoming call ringing
  Future<VoiceCallOperationResult> stopIncomingCallRinging() async {
    try {
      await _handleIncomingCallUseCase.stopRinging();

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure(
        'Error stopping incoming call ringing: $e',
      );
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
    required final VoiceCallState callState,
  }) async {
    try {
      await _endCallUseCase.execute(
        callState: callState,
      ); // ✅ Bounded Context Abstraction

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('Error ending voice call: $e');
    }
  }

  /// 🎯 **Complex Flow Coordination Methods**
  /// These methods handle the complex orchestration that was in the controller

  /// Coordinate complete incoming call flow with timeout management
  Future<IncomingCallFlowResult> coordinateIncomingCallFlow({
    required final VoiceCallState initialState,
    required final Function(VoiceCallState) onStateChange,
    final Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // Start incoming call handling
      final handleResult = await handleIncomingCall();
      if (!handleResult.success) {
        return IncomingCallFlowResult.failure(
          handleResult.errorMessage ?? 'Failed to handle incoming call',
        );
      }

      // Set up timeout timer
      Timer? timeoutTimer;
      final completer = Completer<IncomingCallFlowResult>();

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(IncomingCallFlowResult.timeout());
        }
      });

      // Return control to UI but provide completion mechanism
      return IncomingCallFlowResult.waitingForAcceptance(
        timeoutTimer: timeoutTimer,
        completer: completer,
      );
    } on Exception catch (e) {
      return IncomingCallFlowResult.failure('Error in incoming call flow: $e');
    }
  }

  /// Coordinate outgoing call startup flow
  Future<OutgoingCallFlowResult> coordinateOutgoingCallFlow({
    required final VoiceCallState initialState,
    required final Function(VoiceCallState) onStateChange,
    required final void Function() onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    try {
      // Start outgoing call
      final startResult = await startOutgoingCall(
        isIncoming: false,
        onCallStarted: onCallStarted,
        onCallEnded: onCallEnded,
      );

      if (!startResult.success) {
        return OutgoingCallFlowResult.failure(
          startResult.errorMessage ?? 'Failed to start outgoing call',
        );
      }

      return OutgoingCallFlowResult.success();
    } on Exception catch (e) {
      return OutgoingCallFlowResult.failure('Error in outgoing call flow: $e');
    }
  }

  /// Coordinate call acceptance and transition to active
  Future<CallAcceptanceResult> coordinateCallAcceptance({
    required final VoiceCallState currentState,
    required final Timer? incomingTimer,
    required final void Function() onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    try {
      // Cancel incoming timer if exists
      incomingTimer?.cancel();

      // Accept the incoming call
      final acceptResult = await acceptIncomingCall();
      if (!acceptResult.success) {
        return CallAcceptanceResult.failure(
          acceptResult.errorMessage ?? 'Failed to accept call',
        );
      }

      // Start the actual call flow
      final startResult = await startOutgoingCall(
        isIncoming: true,
        onCallStarted: onCallStarted,
        onCallEnded: onCallEnded,
      );

      if (!startResult.success) {
        return CallAcceptanceResult.failure(
          startResult.errorMessage ?? 'Failed to start accepted call',
        );
      }

      return CallAcceptanceResult.success();
    } on Exception catch (e) {
      return CallAcceptanceResult.failure('Error accepting call: $e');
    }
  }

  /// 🔧 **Private Helper - Execute Start Call**
  /// Common logic for starting calls with proper error handling
  Future<VoiceCallOperationResult> _executeStartCall({
    required final bool isIncoming,
    required final void Function() onCallStarted,
    required final Function(CallEndReason) onCallEnded,
    required final String errorMessage,
  }) async {
    try {
      await _startCallUseCase.execute(
        isIncoming: isIncoming,
        onCallStarted: onCallStarted,
        onCallEnded: onCallEnded,
      );

      return VoiceCallOperationResult.success();
    } on Exception catch (e) {
      return VoiceCallOperationResult.failure('$errorMessage: $e');
    }
  }
}

/// 🎯 **Result Objects for Voice Call Operations**

class VoiceCallInitializationResult {
  factory VoiceCallInitializationResult.success() =>
      const VoiceCallInitializationResult(success: true);

  factory VoiceCallInitializationResult.failure(final String errorMessage) =>
      VoiceCallInitializationResult(success: false, errorMessage: errorMessage);
  const VoiceCallInitializationResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

class VoiceCallOperationResult {
  factory VoiceCallOperationResult.success() =>
      const VoiceCallOperationResult(success: true);

  factory VoiceCallOperationResult.failure(final String errorMessage) =>
      VoiceCallOperationResult(success: false, errorMessage: errorMessage);
  const VoiceCallOperationResult({required this.success, this.errorMessage});

  final bool success;
  final String? errorMessage;
}

/// Complex Flow Result Objects

class IncomingCallFlowResult {
  const IncomingCallFlowResult({
    required this.success,
    this.isTimeout = false,
    this.isWaiting = false,
    this.errorMessage,
    this.timeoutTimer,
    this.completer,
  });

  factory IncomingCallFlowResult.success() =>
      const IncomingCallFlowResult(success: true);

  factory IncomingCallFlowResult.failure(final String errorMessage) =>
      IncomingCallFlowResult(success: false, errorMessage: errorMessage);

  factory IncomingCallFlowResult.timeout() =>
      const IncomingCallFlowResult(success: false, isTimeout: true);

  factory IncomingCallFlowResult.waitingForAcceptance({
    required final Timer timeoutTimer,
    required final Completer<IncomingCallFlowResult> completer,
  }) => IncomingCallFlowResult(
    success: true,
    isWaiting: true,
    timeoutTimer: timeoutTimer,
    completer: completer,
  );

  final bool success;
  final bool isTimeout;
  final bool isWaiting;
  final String? errorMessage;
  final Timer? timeoutTimer;
  final Completer<IncomingCallFlowResult>? completer;
}

class OutgoingCallFlowResult {
  const OutgoingCallFlowResult({required this.success, this.errorMessage});

  factory OutgoingCallFlowResult.success() =>
      const OutgoingCallFlowResult(success: true);

  factory OutgoingCallFlowResult.failure(final String errorMessage) =>
      OutgoingCallFlowResult(success: false, errorMessage: errorMessage);

  final bool success;
  final String? errorMessage;
}

class CallAcceptanceResult {
  const CallAcceptanceResult({required this.success, this.errorMessage});

  factory CallAcceptanceResult.success() =>
      const CallAcceptanceResult(success: true);

  factory CallAcceptanceResult.failure(final String errorMessage) =>
      CallAcceptanceResult(success: false, errorMessage: errorMessage);

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
