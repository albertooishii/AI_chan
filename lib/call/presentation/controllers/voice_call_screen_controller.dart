import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/application/services/voice_call_application_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/call/presentation/interfaces/i_voice_call_screen_controller.dart';

class VoiceCallScreenController extends ChangeNotifier
    implements IVoiceCallScreenController {
  VoiceCallScreenController({
    required final CallType callType,
    required final VoiceCallApplicationService
    voiceCallService, // ✅ DDD: Application Service injection
  }) : _state = VoiceCallState(type: callType),
       _voiceCallService =
           voiceCallService; // ✅ DDD: Single Application Service dependency

  final VoiceCallApplicationService
  _voiceCallService; // ✅ DDD: Coordinated use cases

  VoiceCallState _state;
  Timer? _incomingAnswerTimer;
  Timer? _noAnswerTimer;
  StreamSubscription? _audioLevelSubscription;

  @override
  VoiceCallState get state => _state;
  @override
  bool get isIncoming => _state.isIncoming;
  @override
  bool get canAccept => _state.canAccept;
  @override
  bool get canHangup => _state.canHangup;
  @override
  bool get showAcceptButton => _state.showAcceptButton;

  void _updateState(final VoiceCallState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    try {
      Log.d(
        '🎯 Inicializando VoiceCallScreenController',
        tag: 'VOICE_CALL_CONTROLLER',
      );

      // ✅ DDD: Use Application Service for coordination
      final initResult = await _voiceCallService.initializeVoiceCall();
      if (!initResult.success) {
        throw Exception(
          initResult.errorMessage ?? 'Failed to initialize voice call',
        );
      }

      // Configurar listeners de audio usando Application Service
      _audioLevelSubscription = _voiceCallService.audioLevelStream.listen(
        (final level) => _updateState(_state.copyWith(soundLevel: level)),
      );

      if (_state.isIncoming) {
        _updateState(_state.copyWith(phase: CallPhase.ringing));
        await _handleIncomingCall();
      } else {
        await _startOutgoingCall();
      }
    } on Exception catch (e) {
      Log.e(
        '❌ Error inicializando controller',
        tag: 'VOICE_CALL_CONTROLLER',
        error: e,
      );
      _updateState(
        _state.copyWith(
          phase: CallPhase.ended,
          endReason: CallEndReason.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _handleIncomingCall() async {
    // Delegate complex incoming call flow to Application Service
    final flowResult = await _voiceCallService.coordinateIncomingCallFlow(
      initialState: _state,
      onStateChange: _updateState,
    );

    if (!flowResult.success) {
      if (flowResult.isTimeout) {
        Log.d(
          '⏰ Timeout llamada entrante no aceptada',
          tag: 'VOICE_CALL_CONTROLLER',
        );
        _endCall(reason: CallEndReason.timeout);
      } else {
        Log.e(
          '❌ Error manejando llamada entrante',
          tag: 'VOICE_CALL_CONTROLLER',
          error: Exception(flowResult.errorMessage),
        );
        _updateState(
          _state.copyWith(
            phase: CallPhase.ended,
            endReason: CallEndReason.error,
            errorMessage: flowResult.errorMessage,
          ),
        );
      }
      return;
    }

    // Set up the timeout timer from the flow result
    if (flowResult.isWaiting && flowResult.timeoutTimer != null) {
      _incomingAnswerTimer = flowResult.timeoutTimer;
    }
  }

  Future<void> acceptIncomingCall() async {
    if (!_state.canAccept) return;

    Log.d('📞 Aceptando llamada entrante', tag: 'VOICE_CALL_CONTROLLER');

    // Delegate complex call acceptance flow to Application Service
    final acceptanceResult = await _voiceCallService.coordinateCallAcceptance(
      currentState: _state,
      incomingTimer: _incomingAnswerTimer,
      onCallStarted: () {
        _updateState(_state.copyWith(phase: CallPhase.active));
      },
      onCallEnded: (final reason) {
        _endCall(reason: reason);
      },
    );

    if (!acceptanceResult.success) {
      Log.e(
        '❌ Error aceptando llamada',
        tag: 'VOICE_CALL_CONTROLLER',
        error: Exception(acceptanceResult.errorMessage),
      );
      _updateState(
        _state.copyWith(
          phase: CallPhase.ended,
          endReason: CallEndReason.error,
          errorMessage: acceptanceResult.errorMessage,
        ),
      );
      return;
    }

    _updateState(
      _state.copyWith(isAccepted: true, phase: CallPhase.connecting),
    );
  }

  Future<void> _startOutgoingCall() async {
    Log.d('📞 Iniciando llamada saliente', tag: 'VOICE_CALL_CONTROLLER');
    _updateState(_state.copyWith(phase: CallPhase.connecting));

    // Delegate outgoing call flow to Application Service
    final flowResult = await _voiceCallService.coordinateOutgoingCallFlow(
      initialState: _state,
      onStateChange: _updateState,
      onCallStarted: () {
        _updateState(_state.copyWith(phase: CallPhase.active));
      },
      onCallEnded: (final reason) {
        _endCall(reason: reason);
      },
    );

    if (!flowResult.success) {
      Log.e(
        '❌ Error iniciando llamada saliente',
        tag: 'VOICE_CALL_CONTROLLER',
        error: Exception(flowResult.errorMessage),
      );
      _updateState(
        _state.copyWith(
          phase: CallPhase.ended,
          endReason: CallEndReason.error,
          errorMessage: flowResult.errorMessage,
        ),
      );
    }
  }

  @override
  Future<void> hangupCall() async {
    if (!_state.canHangup) return;
    await _endCall(reason: CallEndReason.hangup);
  }

  void toggleMute() {
    final newMuted = !_state.isMuted;
    // ✅ DDD: Use Application Service for audio management
    _voiceCallService.setAudioMuted(newMuted);
    _updateState(_state.copyWith(isMuted: newMuted));
    Log.d(
      '🎤 Micrófono ${newMuted ? "silenciado" : "activado"}',
      tag: 'VOICE_CALL_CONTROLLER',
    );
  }

  Future<void> _endCall({required final CallEndReason reason}) async {
    if (_state.hangupInProgress) return;

    try {
      Log.d('🔚 Finalizando llamada: $reason', tag: 'VOICE_CALL_CONTROLLER');

      _updateState(
        _state.copyWith(
          hangupInProgress: true,
          phase: CallPhase.ending,
          endReason: reason,
        ),
      );

      // Cancelar timers
      _incomingAnswerTimer?.cancel();
      _noAnswerTimer?.cancel();

      // ✅ DDD: Use Application Service for call termination coordination
      final result = await _voiceCallService.endVoiceCall(
        callState: _state,
      ); // ✅ Bounded Context Abstraction

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Failed to end call');
      }

      _updateState(_state.copyWith(phase: CallPhase.ended));
    } on Exception catch (e) {
      Log.e(
        '❌ Error finalizando llamada',
        tag: 'VOICE_CALL_CONTROLLER',
        error: e,
      );
      _updateState(
        _state.copyWith(phase: CallPhase.ended, errorMessage: e.toString()),
      );
    }
  }

  @override
  void dispose() {
    Log.d(
      '🗑️ Disposing VoiceCallScreenController',
      tag: 'VOICE_CALL_CONTROLLER',
    );

    _incomingAnswerTimer?.cancel();
    _noAnswerTimer?.cancel();
    _audioLevelSubscription?.cancel();

    // ✅ DDD: Use Application Service for proper disposal
    _voiceCallService.dispose();

    super.dispose();
  }

  /// Accept incoming call - interface implementation
  @override
  Future<void> acceptCall() async {
    // Placeholder - delegate to existing logic if available
    debugPrint('Accepting call');
  }

  /// Start outgoing call - interface implementation
  @override
  Future<void> startOutgoingCall() async {
    // Placeholder - delegate to existing logic if available
    debugPrint('Starting outgoing call');
  }

  /// Update connection state - interface implementation
  @override
  void updateConnectionState(final String quality) {
    // Placeholder - update connection quality
    debugPrint('Connection quality: $quality');
  }
}
