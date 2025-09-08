import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/voice_call_state.dart';
import '../../../shared/domain/models/voice_call_message.dart';
import '../../application/services/call_state_application_service.dart';

/// Call State Controller - Compact state and timing management
class CallStateController extends ChangeNotifier {
  // Application Service for business logic
  final CallStateApplicationService _applicationService =
      CallStateApplicationService();
  // Core state
  CallPhase _currentPhase = CallPhase.initializing;
  CallPhase? _previousPhase;
  final List<VoiceCallMessage> _messageHistory = [];
  bool _isUserTurn = true, _isAiSpeaking = false;
  DateTime? _callStartTime, _callEndTime, _lastMessageTime;
  Timer? _callDurationTimer, _phaseTimeoutTimer;
  Duration _callDuration = Duration.zero, _currentPhaseDuration = Duration.zero;
  CallEndReason? _terminationReason;

  // Statistics
  int _userMessageCount = 0, _aiMessageCount = 0, _phaseTransitionCount = 0;
  Duration _totalUserSpeakTime = Duration.zero,
      _totalAiSpeakTime = Duration.zero;

  // Getters
  CallPhase get currentPhase => _currentPhase;
  CallPhase? get previousPhase => _previousPhase;
  List<VoiceCallMessage> get messageHistory =>
      List.unmodifiable(_messageHistory);
  bool get isUserTurn => _isUserTurn;
  bool get isAiSpeaking => _isAiSpeaking;
  DateTime? get callStartTime => _callStartTime;
  DateTime? get callEndTime => _callEndTime;
  DateTime? get lastMessageTime => _lastMessageTime;
  Duration get callDuration => _callDuration;
  Duration get currentPhaseDuration => _currentPhaseDuration;
  CallEndReason? get terminationReason => _terminationReason;
  int get userMessageCount => _userMessageCount;
  int get aiMessageCount => _aiMessageCount;
  int get totalMessageCount => _userMessageCount + _aiMessageCount;
  int get phaseTransitionCount => _phaseTransitionCount;
  Duration get totalUserSpeakTime => _totalUserSpeakTime;
  Duration get totalAiSpeakTime => _totalAiSpeakTime;
  bool get isCallActive => _currentPhase != CallPhase.ended;

  /// Transition to new call phase using Application Service
  void transitionToPhase(final CallPhase newPhase, {final String? reason}) {
    try {
      final result = _applicationService.coordinatePhaseTransition(
        _currentPhase,
        newPhase,
        reason: reason,
        currentPhaseDuration: _currentPhaseDuration,
      );

      if (result.success) {
        _previousPhase = result.previousPhase;
        _currentPhase = result.newPhase;
        _phaseTransitionCount++;
        _currentPhaseDuration = Duration.zero;
        _handlePhaseTransition(result.newPhase, result.reason);
        notifyListeners();
        debugPrint(
          '📞 [STATE] Phase: ${result.previousPhase} → ${result.newPhase} ${result.reason != null ? "(${result.reason})" : ""}',
        );
      } else {
        debugPrint('❌ [STATE] Phase transition failed: ${result.error}');
      }
    } on Exception catch (e) {
      debugPrint('Error in transitionToPhase: $e');
    }
  }

  /// Add message to history using Application Service
  void addMessage(final VoiceCallMessage message) {
    try {
      final result = _applicationService.coordinateMessageAddition(
        message,
        _messageHistory,
        _isUserTurn,
      );

      if (result.success) {
        _messageHistory.add(message);
        _lastMessageTime = result.lastMessageTime;
        _isUserTurn = result.newUserTurn;

        if (message.isUser) {
          _userMessageCount++;
        } else {
          _aiMessageCount++;
        }

        notifyListeners();
        debugPrint(
          '💬 [STATE] Message added: ${message.isUser ? "USER" : "AI"} (${result.totalMessageCount} total)',
        );
      } else {
        debugPrint('❌ [STATE] Message addition failed: ${result.error}');
      }
    } on Exception catch (e) {
      debugPrint('Error in addMessage: $e');
    }
  }

  /// Turn management
  void setUserTurn(final bool isUserTurn) {
    try {
      _isUserTurn = isUserTurn;
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Error in setUserTurn: $e');
    }
  }

  void setAiSpeaking(final bool isAiSpeaking) {
    try {
      _isAiSpeaking = isAiSpeaking;
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Error in setAiSpeaking: $e');
    }
  }

  /// Start call timing using Application Service
  void startCall() {
    try {
      final result = _applicationService.coordinateCallTiming(isStarting: true);

      if (result.success) {
        _callStartTime = result.callStartTime;
        _startCallDurationTimer();
        transitionToPhase(CallPhase.connecting);
        notifyListeners();
        debugPrint('▶️ [STATE] Call started at ${result.callStartTime}');
      } else {
        debugPrint('❌ [STATE] Call start failed: ${result.error}');
      }
    } on Exception catch (e) {
      debugPrint('Error in startCall: $e');
    }
  }

  /// End call with reason using Application Service
  void endCall({final CallEndReason reason = CallEndReason.hangup}) {
    try {
      final result = _applicationService.coordinateCallTiming(
        isStarting: false,
        callStartTime: _callStartTime,
        endReason: reason,
      );

      if (result.success) {
        _callEndTime = result.callEndTime;
        _terminationReason = reason;
        _stopTimers();
        transitionToPhase(CallPhase.ended);
        notifyListeners();
        debugPrint(
          '⏹️ [STATE] Call ended: $reason (Duration: ${result.callDuration})',
        );
      } else {
        debugPrint('❌ [STATE] Call end failed: ${result.error}');
      }
    } on Exception catch (e) {
      debugPrint('Error in endCall: $e');
    }
  }

  /// Add speaking time tracking using Application Service
  void addUserSpeakTime(final Duration duration) {
    try {
      if (_applicationService.coordinateSpeakingTimeUpdate(
        _totalUserSpeakTime,
        duration,
      )) {
        _totalUserSpeakTime += duration;
        notifyListeners();
      }
    } on Exception catch (e) {
      debugPrint('Error in addUserSpeakTime: $e');
    }
  }

  void addAiSpeakTime(final Duration duration) {
    try {
      if (_applicationService.coordinateSpeakingTimeUpdate(
        _totalAiSpeakTime,
        duration,
      )) {
        _totalAiSpeakTime += duration;
        notifyListeners();
      }
    } on Exception catch (e) {
      debugPrint('Error in addAiSpeakTime: $e');
    }
  }

  /// Get call statistics and conversation summary using Application Service
  Map<String, dynamic> getCallStatistics() => _getCallAnalysis().statistics;
  Map<String, dynamic> getConversationSummary() =>
      _getCallAnalysis().conversationSummary;

  /// Check if phase timeout should trigger using Application Service
  bool shouldTimeoutPhase() => _getCallAnalysis().shouldTriggerTimeout;

  // Private helper for Application Service call
  CallStatisticsAnalysisResult _getCallAnalysis() =>
      _applicationService.analyzeCallStatistics(
        currentPhase: _currentPhase,
        callDuration: _callDuration,
        currentPhaseDuration: _currentPhaseDuration,
        userMessageCount: _userMessageCount,
        aiMessageCount: _aiMessageCount,
        phaseTransitionCount: _phaseTransitionCount,
        totalUserSpeakTime: _totalUserSpeakTime,
        totalAiSpeakTime: _totalAiSpeakTime,
        messageHistory: _messageHistory,
        terminationReason: _terminationReason,
      );

  /// Reset all state
  void resetState() {
    try {
      final result = _applicationService.coordinateStateReset();

      if (result.success) {
        _stopTimers();
        _applyResetValues(result.resetValues);
        _messageHistory.clear();
        notifyListeners();
        debugPrint('🔄 [STATE] State reset complete');
      } else {
        debugPrint('❌ [STATE] State reset failed: ${result.error}');
      }
    } on Exception catch (e) {
      debugPrint('Error in resetState: $e');
    }
  }

  // Private helper for applying reset values from Application Service
  void _applyResetValues(final CallStateResetValues resetValues) {
    _currentPhase = resetValues.phase;
    _previousPhase = null;
    _isUserTurn = resetValues.isUserTurn;
    _isAiSpeaking = resetValues.isAiSpeaking;
    _callStartTime = resetValues.callStartTime;
    _callEndTime = resetValues.callEndTime;
    _lastMessageTime = resetValues.lastMessageTime;
    _callDuration = resetValues.callDuration;
    _currentPhaseDuration = resetValues.currentPhaseDuration;
    _terminationReason = resetValues.terminationReason;
    _userMessageCount = resetValues.userMessageCount;
    _aiMessageCount = resetValues.aiMessageCount;
    _phaseTransitionCount = resetValues.phaseTransitionCount;
    _totalUserSpeakTime = resetValues.totalUserSpeakTime;
    _totalAiSpeakTime = resetValues.totalAiSpeakTime;
  }

  // Private helpers - simplified with Application Service delegation
  void _handlePhaseTransition(final CallPhase newPhase, final String? reason) {
    final timerResult = _applicationService.coordinateTimerManagement(
      newPhase,
      _previousPhase,
    );

    if (timerResult.success) {
      if (timerResult.shouldStartCallTimer) {
        _startCallDurationTimer();
      } else if (timerResult.shouldStartPhaseTimer &&
          timerResult.phaseTimeoutDuration != null) {
        _setPhaseTimeout(timerResult.phaseTimeoutDuration!);
      } else if (timerResult.shouldStopAllTimers) {
        _stopTimers();
      }
    }
  }

  void _startCallDurationTimer() {
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final result = _applicationService.coordinateDurationUpdate(
        _callStartTime,
        _currentPhaseDuration,
      );

      if (result.success) {
        _callDuration = result.callDuration;
        _currentPhaseDuration = result.currentPhaseDuration;
        notifyListeners();
      }
    });
  }

  void _setPhaseTimeout(final Duration timeout) {
    _clearPhaseTimeout();
    _phaseTimeoutTimer = Timer(timeout, () {
      debugPrint('⏰ [STATE] Phase timeout: $_currentPhase');
      endCall(reason: CallEndReason.timeout);
    });
  }

  void _clearPhaseTimeout() => _phaseTimeoutTimer?.cancel();

  void _stopTimers() {
    _callDurationTimer?.cancel();
    _clearPhaseTimeout();
    _callDurationTimer = null;
    _phaseTimeoutTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}
