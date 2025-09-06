import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/application/services/voice_call_application_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro

class VoiceCallScreenController extends ChangeNotifier {
  VoiceCallScreenController({
    required final ChatController chatController, // ✅ DDD: ETAPA 3 - DDD puro
    required final CallType callType,
    required final VoiceCallApplicationService voiceCallService, // ✅ DDD: Application Service injection
  }) : _chatController = chatController, // ✅ DDD: ETAPA 3
       _state = VoiceCallState(type: callType),
       _voiceCallService = voiceCallService; // ✅ DDD: Single Application Service dependency

  final ChatController _chatController; // ✅ DDD: ETAPA 3 - DDD puro
  final VoiceCallApplicationService _voiceCallService; // ✅ DDD: Coordinated use cases

  VoiceCallState _state;
  Timer? _incomingAnswerTimer;
  Timer? _noAnswerTimer;
  StreamSubscription? _audioLevelSubscription;

  VoiceCallState get state => _state;
  bool get isIncoming => _state.isIncoming;
  bool get canAccept => _state.canAccept;
  bool get canHangup => _state.canHangup;
  bool get showAcceptButton => _state.showAcceptButton;

  void _updateState(final VoiceCallState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    try {
      Log.d('🎯 Inicializando VoiceCallScreenController', tag: 'VOICE_CALL_CONTROLLER');

      // ✅ DDD: Use Application Service for coordination
      final initResult = await _voiceCallService.initializeVoiceCall();
      if (!initResult.success) {
        throw Exception(initResult.errorMessage ?? 'Failed to initialize voice call');
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
      Log.e('❌ Error inicializando controller', tag: 'VOICE_CALL_CONTROLLER', error: e);
      _updateState(_state.copyWith(phase: CallPhase.ended, endReason: CallEndReason.error, errorMessage: e.toString()));
    }
  }

  Future<void> _handleIncomingCall() async {
    try {
      // ✅ DDD: Use Application Service for incoming call coordination
      final result = await _voiceCallService.handleIncomingCall();
      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Failed to handle incoming call');
      }

      // Timeout para llamada entrante no aceptada
      _incomingAnswerTimer = Timer(const Duration(seconds: 10), () {
        if (!_state.isAccepted && _state.phase == CallPhase.ringing) {
          Log.d('⏰ Timeout llamada entrante no aceptada', tag: 'VOICE_CALL_CONTROLLER');
          _endCall(reason: CallEndReason.timeout);
        }
      });
    } on Exception catch (e) {
      Log.e('❌ Error manejando llamada entrante', tag: 'VOICE_CALL_CONTROLLER', error: e);
      _updateState(_state.copyWith(phase: CallPhase.ended, endReason: CallEndReason.error, errorMessage: e.toString()));
    }
  }

  Future<void> acceptIncomingCall() async {
    if (!_state.canAccept) return;

    try {
      Log.d('📞 Aceptando llamada entrante', tag: 'VOICE_CALL_CONTROLLER');

      _incomingAnswerTimer?.cancel();

      // ✅ DDD: Use Application Service for accepting incoming call
      final result = await _voiceCallService.acceptIncomingCall();
      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Failed to accept incoming call');
      }

      _updateState(_state.copyWith(isAccepted: true, phase: CallPhase.connecting));

      await _startCallInternal();
    } on Exception catch (e) {
      Log.e('❌ Error aceptando llamada', tag: 'VOICE_CALL_CONTROLLER', error: e);
      _updateState(_state.copyWith(phase: CallPhase.ended, endReason: CallEndReason.error, errorMessage: e.toString()));
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      Log.d('📞 Iniciando llamada saliente', tag: 'VOICE_CALL_CONTROLLER');
      _updateState(_state.copyWith(phase: CallPhase.connecting));
      await _startCallInternal();
    } on Exception catch (e) {
      Log.e('❌ Error iniciando llamada saliente', tag: 'VOICE_CALL_CONTROLLER', error: e);
      _updateState(_state.copyWith(phase: CallPhase.ended, endReason: CallEndReason.error, errorMessage: e.toString()));
    }
  }

  Future<void> _startCallInternal() async {
    try {
      // TODO: En el futuro, el sistema será más complejo y manejará el prompt del sistema
      // Por ahora, simplemente iniciamos la llamada

      // ✅ DDD: Use Application Service for call start coordination
      final result = await _voiceCallService.startCallInternal(
        isIncoming: _state.isIncoming,
        onCallStarted: () => _updateState(_state.copyWith(phase: CallPhase.active)),
        onCallEnded: (final reason) => _endCall(reason: reason),
      );

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Failed to start call');
      }
    } on Exception catch (e) {
      Log.e('❌ Error en _startCallInternal', tag: 'VOICE_CALL_CONTROLLER', error: e);
      _updateState(_state.copyWith(phase: CallPhase.ended, endReason: CallEndReason.error, errorMessage: e.toString()));
    }
  }

  void toggleMute() {
    final newMuted = !_state.isMuted;
    // ✅ DDD: Use Application Service for audio management
    _voiceCallService.setAudioMuted(newMuted);
    _updateState(_state.copyWith(isMuted: newMuted));
    Log.d('🎤 Micrófono ${newMuted ? "silenciado" : "activado"}', tag: 'VOICE_CALL_CONTROLLER');
  }

  Future<void> hangUp() async {
    if (!_state.canHangup) return;
    await _endCall(reason: CallEndReason.hangup);
  }

  Future<void> _endCall({required final CallEndReason reason}) async {
    if (_state.hangupInProgress) return;

    try {
      Log.d('🔚 Finalizando llamada: $reason', tag: 'VOICE_CALL_CONTROLLER');

      _updateState(_state.copyWith(hangupInProgress: true, phase: CallPhase.ending, endReason: reason));

      // Cancelar timers
      _incomingAnswerTimer?.cancel();
      _noAnswerTimer?.cancel();

      // ✅ DDD: Use Application Service for call termination coordination
      final result = await _voiceCallService.endVoiceCall(
        chatController: _chatController,
        callState: _state,
      ); // ✅ DDD: ETAPA 3

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Failed to end call');
      }

      _updateState(_state.copyWith(phase: CallPhase.ended));
    } on Exception catch (e) {
      Log.e('❌ Error finalizando llamada', tag: 'VOICE_CALL_CONTROLLER', error: e);
      _updateState(_state.copyWith(phase: CallPhase.ended, errorMessage: e.toString()));
    }
  }

  @override
  void dispose() {
    Log.d('🗑️ Disposing VoiceCallScreenController', tag: 'VOICE_CALL_CONTROLLER');

    _incomingAnswerTimer?.cancel();
    _noAnswerTimer?.cancel();
    _audioLevelSubscription?.cancel();

    // ✅ DDD: Use Application Service for proper disposal
    _voiceCallService.dispose();

    super.dispose();
  }
}
