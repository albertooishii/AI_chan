import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/application/use_cases/start_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/end_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/handle_incoming_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/manage_audio_use_case.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class VoiceCallScreenController extends ChangeNotifier {
  final ChatProvider _chatProvider;
  final StartCallUseCase _startCallUseCase;
  final EndCallUseCase _endCallUseCase;
  final HandleIncomingCallUseCase _handleIncomingCallUseCase;
  final ManageAudioUseCase _manageAudioUseCase;

  VoiceCallState _state;
  Timer? _incomingAnswerTimer;
  Timer? _noAnswerTimer;
  StreamSubscription? _audioLevelSubscription;

  VoiceCallScreenController({
    required ChatProvider chatProvider,
    required CallController callController,
    required CallType callType,
    StartCallUseCase? startCallUseCase,
    EndCallUseCase? endCallUseCase,
    HandleIncomingCallUseCase? handleIncomingCallUseCase,
    ManageAudioUseCase? manageAudioUseCase,
  }) : _chatProvider = chatProvider,
       _state = VoiceCallState(type: callType),
       _startCallUseCase = startCallUseCase ?? StartCallUseCase(callController),
       _endCallUseCase = endCallUseCase ?? EndCallUseCase(callController),
       _handleIncomingCallUseCase =
           handleIncomingCallUseCase ??
           HandleIncomingCallUseCase(callController),
       _manageAudioUseCase =
           manageAudioUseCase ?? ManageAudioUseCase(callController);

  VoiceCallState get state => _state;
  bool get isIncoming => _state.isIncoming;
  bool get canAccept => _state.canAccept;
  bool get canHangup => _state.canHangup;
  bool get showAcceptButton => _state.showAcceptButton;

  void _updateState(VoiceCallState newState) {
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

      // Configurar audio management
      await _manageAudioUseCase.initialize();

      // Configurar listeners de audio
      _audioLevelSubscription = _manageAudioUseCase.audioLevelStream.listen(
        (level) => _updateState(_state.copyWith(soundLevel: level)),
      );

      if (_state.isIncoming) {
        _updateState(_state.copyWith(phase: CallPhase.ringing));
        await _handleIncomingCall();
      } else {
        await _startOutgoingCall();
      }
    } catch (e) {
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
    try {
      await _handleIncomingCallUseCase.startRinging();

      // Timeout para llamada entrante no aceptada
      _incomingAnswerTimer = Timer(const Duration(seconds: 10), () {
        if (!_state.isAccepted && _state.phase == CallPhase.ringing) {
          Log.d(
            '⏰ Timeout llamada entrante no aceptada',
            tag: 'VOICE_CALL_CONTROLLER',
          );
          _endCall(reason: CallEndReason.timeout);
        }
      });
    } catch (e) {
      Log.e(
        '❌ Error manejando llamada entrante',
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

  Future<void> acceptIncomingCall() async {
    if (!_state.canAccept) return;

    try {
      Log.d('📞 Aceptando llamada entrante', tag: 'VOICE_CALL_CONTROLLER');

      _incomingAnswerTimer?.cancel();
      await _handleIncomingCallUseCase.stopRinging();

      _updateState(
        _state.copyWith(isAccepted: true, phase: CallPhase.connecting),
      );

      await _startCallInternal();
    } catch (e) {
      Log.e(
        '❌ Error aceptando llamada',
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

  Future<void> _startOutgoingCall() async {
    try {
      Log.d('📞 Iniciando llamada saliente', tag: 'VOICE_CALL_CONTROLLER');
      _updateState(_state.copyWith(phase: CallPhase.connecting));
      await _startCallInternal();
    } catch (e) {
      Log.e(
        '❌ Error iniciando llamada saliente',
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

  Future<void> _startCallInternal() async {
    try {
      final systemPrompt = _chatProvider.buildCallSystemPromptJson(
        aiInitiatedCall: _state.isIncoming,
      );

      await _startCallUseCase.execute(
        systemPrompt: systemPrompt,
        isIncoming: _state.isIncoming,
        onTextReceived: _handleAIText,
        onUserTranscription: _handleUserTranscription,
        onCallStarted: () =>
            _updateState(_state.copyWith(phase: CallPhase.active)),
        onCallEnded: (reason) => _endCall(reason: reason),
      );
    } catch (e) {
      Log.e(
        '❌ Error en _startCallInternal',
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

  void _handleAIText(String text) {
    _updateState(_state.copyWith(aiText: _state.aiText + text));

    // Detectar tags de control
    if (text.contains('[start_call]')) {
      _updateState(_state.copyWith(startCallTagReceived: true));
    }

    if (text.contains('[end_call]')) {
      _updateState(_state.copyWith(endCallTagReceived: true));
      _endCall(reason: CallEndReason.hangup);
    }
  }

  void _handleUserTranscription(String transcription) {
    _updateState(
      _state.copyWith(userText: '${_state.userText}$transcription '),
    );
  }

  void toggleMute() {
    final newMuted = !_state.isMuted;
    _manageAudioUseCase.setMuted(newMuted);
    _updateState(_state.copyWith(isMuted: newMuted));
    Log.d(
      '🎤 Micrófono ${newMuted ? "silenciado" : "activado"}',
      tag: 'VOICE_CALL_CONTROLLER',
    );
  }

  Future<void> hangUp() async {
    if (!_state.canHangup) return;
    await _endCall(reason: CallEndReason.hangup);
  }

  Future<void> _endCall({required CallEndReason reason}) async {
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

      await _endCallUseCase.execute(
        chatProvider: _chatProvider,
        callState: _state,
      );

      _updateState(_state.copyWith(phase: CallPhase.ended));
    } catch (e) {
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

    _manageAudioUseCase.dispose();

    super.dispose();
  }
}
