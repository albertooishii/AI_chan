import '../../domain/entities/voice_call_state.dart';
import '../../domain/entities/voice_call_message.dart';

/// Result objects for DDD pattern compliance
class CallPhaseTransitionResult {
  const CallPhaseTransitionResult({
    required this.success,
    required this.newPhase,
    this.previousPhase,
    this.reason,
    this.error,
  });

  factory CallPhaseTransitionResult.success(
    final CallPhase newPhase,
    final CallPhase? previousPhase, {
    final String? reason,
  }) => CallPhaseTransitionResult(
    success: true,
    newPhase: newPhase,
    previousPhase: previousPhase,
    reason: reason,
  );

  factory CallPhaseTransitionResult.failure(final String error) =>
      CallPhaseTransitionResult(
        success: false,
        newPhase: CallPhase.ended,
        error: error,
      );
  final bool success;
  final CallPhase newPhase;
  final CallPhase? previousPhase;
  final String? reason;
  final String? error;
}

class CallTimingCoordinationResult {
  const CallTimingCoordinationResult({
    required this.success,
    this.callStartTime,
    this.callEndTime,
    this.callDuration = Duration.zero,
    this.currentPhaseDuration = Duration.zero,
    this.error,
  });

  factory CallTimingCoordinationResult.success({
    final DateTime? startTime,
    final DateTime? endTime,
    final Duration? duration,
    final Duration? phaseDuration,
  }) => CallTimingCoordinationResult(
    success: true,
    callStartTime: startTime,
    callEndTime: endTime,
    callDuration: duration ?? Duration.zero,
    currentPhaseDuration: phaseDuration ?? Duration.zero,
  );

  factory CallTimingCoordinationResult.failure(final String error) =>
      CallTimingCoordinationResult(success: false, error: error);
  final bool success;
  final DateTime? callStartTime;
  final DateTime? callEndTime;
  final Duration callDuration;
  final Duration currentPhaseDuration;
  final String? error;
}

class CallDurationUpdateResult {
  const CallDurationUpdateResult({
    required this.success,
    required this.callDuration,
    required this.currentPhaseDuration,
    this.error,
  });

  factory CallDurationUpdateResult.success(
    final Duration callDuration,
    final Duration phaseDuration,
  ) => CallDurationUpdateResult(
    success: true,
    callDuration: callDuration,
    currentPhaseDuration: phaseDuration,
  );

  factory CallDurationUpdateResult.failure(final String error) =>
      CallDurationUpdateResult(
        success: false,
        callDuration: Duration.zero,
        currentPhaseDuration: Duration.zero,
        error: error,
      );
  final bool success;
  final Duration callDuration;
  final Duration currentPhaseDuration;
  final String? error;
}

class CallTimerCoordinationResult {
  const CallTimerCoordinationResult({
    required this.success,
    required this.shouldStartCallTimer,
    required this.shouldStartPhaseTimer,
    required this.shouldStopAllTimers,
    this.phaseTimeoutDuration,
    this.error,
  });

  factory CallTimerCoordinationResult.callStart() =>
      const CallTimerCoordinationResult(
        success: true,
        shouldStartCallTimer: true,
        shouldStartPhaseTimer: false,
        shouldStopAllTimers: false,
      );

  factory CallTimerCoordinationResult.phaseTimeout(
    final Duration timeoutDuration,
  ) => CallTimerCoordinationResult(
    success: true,
    shouldStartCallTimer: false,
    shouldStartPhaseTimer: true,
    shouldStopAllTimers: false,
    phaseTimeoutDuration: timeoutDuration,
  );

  factory CallTimerCoordinationResult.stopAll() =>
      const CallTimerCoordinationResult(
        success: true,
        shouldStartCallTimer: false,
        shouldStartPhaseTimer: false,
        shouldStopAllTimers: true,
      );

  factory CallTimerCoordinationResult.noAction() =>
      const CallTimerCoordinationResult(
        success: true,
        shouldStartCallTimer: false,
        shouldStartPhaseTimer: false,
        shouldStopAllTimers: false,
      );

  factory CallTimerCoordinationResult.failure(final String error) =>
      CallTimerCoordinationResult(
        success: false,
        shouldStartCallTimer: false,
        shouldStartPhaseTimer: false,
        shouldStopAllTimers: false,
        error: error,
      );
  final bool success;
  final bool shouldStartCallTimer;
  final bool shouldStartPhaseTimer;
  final bool shouldStopAllTimers;
  final Duration? phaseTimeoutDuration;
  final String? error;
}

class CallStateResetResult {
  const CallStateResetResult({
    required this.success,
    required this.resetValues,
    this.error,
  });

  factory CallStateResetResult.success() => const CallStateResetResult(
    success: true,
    resetValues: CallStateResetValues(),
  );

  factory CallStateResetResult.failure(final String error) =>
      CallStateResetResult(
        success: false,
        resetValues: const CallStateResetValues(),
        error: error,
      );
  final bool success;
  final CallStateResetValues resetValues;
  final String? error;
}

class CallStateResetValues {
  const CallStateResetValues({
    this.phase = CallPhase.initializing,
    this.isUserTurn = true,
    this.isAiSpeaking = false,
    this.userMessageCount = 0,
    this.aiMessageCount = 0,
    this.phaseTransitionCount = 0,
    this.callStartTime,
    this.callEndTime,
    this.lastMessageTime,
    this.callDuration = Duration.zero,
    this.currentPhaseDuration = Duration.zero,
    this.terminationReason,
    this.totalUserSpeakTime = Duration.zero,
    this.totalAiSpeakTime = Duration.zero,
  });
  final CallPhase phase;
  final bool isUserTurn;
  final bool isAiSpeaking;
  final int userMessageCount;
  final int aiMessageCount;
  final int phaseTransitionCount;
  final DateTime? callStartTime;
  final DateTime? callEndTime;
  final DateTime? lastMessageTime;
  final Duration callDuration;
  final Duration currentPhaseDuration;
  final CallEndReason? terminationReason;
  final Duration totalUserSpeakTime;
  final Duration totalAiSpeakTime;
}

class CallStatisticsAnalysisResult {
  const CallStatisticsAnalysisResult({
    required this.statistics,
    required this.conversationSummary,
    required this.averageResponseTime,
    required this.conversationBalance,
    required this.shouldTriggerTimeout,
  });
  final Map<String, dynamic> statistics;
  final Map<String, dynamic> conversationSummary;
  final double averageResponseTime;
  final double conversationBalance;
  final bool shouldTriggerTimeout;
}

class CallMessageCoordinationResult {
  const CallMessageCoordinationResult({
    required this.success,
    this.message,
    required this.newUserTurn,
    required this.totalMessageCount,
    this.lastMessageTime,
    this.error,
  });

  factory CallMessageCoordinationResult.success(
    final VoiceCallMessage message,
    final bool newUserTurn,
    final int totalCount,
  ) => CallMessageCoordinationResult(
    success: true,
    message: message,
    newUserTurn: newUserTurn,
    totalMessageCount: totalCount,
    lastMessageTime: DateTime.now(),
  );

  factory CallMessageCoordinationResult.failure(final String error) =>
      CallMessageCoordinationResult(
        success: false,
        newUserTurn: false,
        totalMessageCount: 0,
        error: error,
      );
  final bool success;
  final VoiceCallMessage? message;
  final bool newUserTurn;
  final int totalMessageCount;
  final DateTime? lastMessageTime;
  final String? error;
}

/// DDD Application Service for Call State coordination and business logic
class CallStateApplicationService {
  /// Coordinate phase transitions with business rules
  CallPhaseTransitionResult coordinatePhaseTransition(
    final CallPhase currentPhase,
    final CallPhase newPhase, {
    final String? reason,
    final Duration? currentPhaseDuration,
  }) {
    try {
      // Business rule: Validate phase transition
      if (!_isValidPhaseTransition(currentPhase, newPhase)) {
        return CallPhaseTransitionResult.failure(
          'Invalid transition from $currentPhase to $newPhase',
        );
      }

      // Business rule: Check if phase change is necessary
      if (currentPhase == newPhase) {
        return CallPhaseTransitionResult.failure('Already in phase $newPhase');
      }

      return CallPhaseTransitionResult.success(
        newPhase,
        currentPhase,
        reason: reason,
      );
    } on Exception catch (e) {
      return CallPhaseTransitionResult.failure('Phase transition failed: $e');
    }
  }

  /// Coordinate call timing and duration management
  CallTimingCoordinationResult coordinateCallTiming({
    required final bool isStarting,
    final DateTime? callStartTime,
    final CallEndReason? endReason,
  }) {
    try {
      final now = DateTime.now();

      if (isStarting) {
        return CallTimingCoordinationResult.success(startTime: now);
      } else {
        // Ending call
        if (callStartTime == null) {
          return CallTimingCoordinationResult.failure(
            'Cannot end call: no start time recorded',
          );
        }

        final duration = now.difference(callStartTime);
        return CallTimingCoordinationResult.success(
          startTime: callStartTime,
          endTime: now,
          duration: duration,
        );
      }
    } on Exception catch (e) {
      return CallTimingCoordinationResult.failure(
        'Timing coordination failed: $e',
      );
    }
  }

  /// Coordinate message addition with turn management
  CallMessageCoordinationResult coordinateMessageAddition(
    final VoiceCallMessage message,
    final List<VoiceCallMessage> currentHistory,
    final bool currentUserTurn,
  ) {
    try {
      // Business rule: Message validation
      if (message.text.trim().isEmpty) {
        return CallMessageCoordinationResult.failure(
          'Empty message not allowed',
        );
      }

      // Business rule: Turn management logic
      final newUserTurn = message.isUser
          ? false
          : true; // User spoke -> AI's turn, AI spoke -> User's turn
      final newTotalCount = currentHistory.length + 1;

      return CallMessageCoordinationResult.success(
        message,
        newUserTurn,
        newTotalCount,
      );
    } on Exception catch (e) {
      return CallMessageCoordinationResult.failure(
        'Message coordination failed: $e',
      );
    }
  }

  /// Analyze call statistics and performance metrics
  CallStatisticsAnalysisResult analyzeCallStatistics({
    required final CallPhase currentPhase,
    required final Duration callDuration,
    required final Duration currentPhaseDuration,
    required final int userMessageCount,
    required final int aiMessageCount,
    required final int phaseTransitionCount,
    required final Duration totalUserSpeakTime,
    required final Duration totalAiSpeakTime,
    required final List<VoiceCallMessage> messageHistory,
    final CallEndReason? terminationReason,
  }) {
    // Calculate statistics
    final statistics = {
      'currentPhase': currentPhase.toString(),
      'callDuration': callDuration.inSeconds,
      'messageCount': userMessageCount + aiMessageCount,
      'userMessages': userMessageCount,
      'aiMessages': aiMessageCount,
      'phaseTransitions': phaseTransitionCount,
      'userSpeakTime': totalUserSpeakTime.inSeconds,
      'aiSpeakTime': totalAiSpeakTime.inSeconds,
      'terminationReason': terminationReason?.toString(),
      'isActive': currentPhase != CallPhase.ended,
    };

    // Calculate conversation metrics
    final totalMessages = userMessageCount + aiMessageCount;
    final averageResponseTime = _calculateAverageResponseTime(messageHistory);
    final conversationBalance = _calculateConversationBalance(
      totalUserSpeakTime,
      totalAiSpeakTime,
    );

    final conversationSummary = {
      'totalMessages': totalMessages,
      'userParticipation': totalMessages > 0
          ? userMessageCount / totalMessages
          : 0.0,
      'averageResponseTime': averageResponseTime,
      'conversationBalance': conversationBalance,
      'lastActivity': messageHistory.isNotEmpty
          ? messageHistory.last.timestamp.toIso8601String()
          : null,
    };

    // Check timeout conditions
    final shouldTimeout = _shouldTimeoutPhase(
      currentPhase,
      currentPhaseDuration,
    );

    return CallStatisticsAnalysisResult(
      statistics: statistics,
      conversationSummary: conversationSummary,
      averageResponseTime: averageResponseTime,
      conversationBalance: conversationBalance,
      shouldTriggerTimeout: shouldTimeout,
    );
  }

  /// Coordinate speaking time tracking
  bool coordinateSpeakingTimeUpdate(
    final Duration currentTime,
    final Duration additionalTime,
  ) {
    try {
      final newTotalTime = currentTime + additionalTime;

      // Business rule: Reasonable speaking time limits
      if (newTotalTime.inMinutes > 120) {
        // 2 hours max
        return false;
      }

      return true;
    } on Exception {
      return false;
    }
  }

  /// Coordinate timer management based on phase transitions
  CallTimerCoordinationResult coordinateTimerManagement(
    final CallPhase newPhase,
    final CallPhase? previousPhase,
  ) {
    try {
      switch (newPhase) {
        case CallPhase.connecting:
          final timeout = getPhaseTimeoutDuration(newPhase);
          return timeout != null
              ? CallTimerCoordinationResult.phaseTimeout(timeout)
              : CallTimerCoordinationResult.noAction();

        case CallPhase.active:
          return CallTimerCoordinationResult.noAction();

        case CallPhase.ended:
          return CallTimerCoordinationResult.stopAll();

        default:
          return CallTimerCoordinationResult.noAction();
      }
    } on Exception catch (e) {
      return CallTimerCoordinationResult.failure(
        'Timer coordination failed: $e',
      );
    }
  }

  /// Calculate updated durations based on call start time
  CallDurationUpdateResult coordinateDurationUpdate(
    final DateTime? callStartTime,
    final Duration currentPhaseDuration,
  ) {
    try {
      if (callStartTime == null) {
        return CallDurationUpdateResult.failure('No call start time available');
      }

      final now = DateTime.now();
      final callDuration = now.difference(callStartTime);
      final newPhaseDuration =
          currentPhaseDuration + const Duration(seconds: 1);

      return CallDurationUpdateResult.success(callDuration, newPhaseDuration);
    } on Exception catch (e) {
      return CallDurationUpdateResult.failure('Duration update failed: $e');
    }
  }

  /// Coordinate complete state reset
  CallStateResetResult coordinateStateReset() {
    try {
      // Business rule: Always reset to safe initial state
      return CallStateResetResult.success();
    } on Exception catch (e) {
      return CallStateResetResult.failure('State reset failed: $e');
    }
  }

  /// Determine phase timeout durations based on business rules
  Duration? getPhaseTimeoutDuration(final CallPhase phase) {
    const phaseTimeouts = <CallPhase, Duration>{
      CallPhase.connecting: Duration(seconds: 30),
      CallPhase.ringing: Duration(seconds: 60),
      CallPhase.active: Duration(minutes: 30),
    };

    return phaseTimeouts[phase];
  }

  // Private business logic methods
  bool _isValidPhaseTransition(final CallPhase from, final CallPhase to) {
    // Define valid state transitions
    const validTransitions = <CallPhase, Set<CallPhase>>{
      CallPhase.initializing: {CallPhase.connecting, CallPhase.ended},
      CallPhase.connecting: {
        CallPhase.ringing,
        CallPhase.active,
        CallPhase.ended,
      },
      CallPhase.ringing: {CallPhase.active, CallPhase.ended},
      CallPhase.active: {CallPhase.ended},
      CallPhase.ended: {CallPhase.initializing}, // Allow restart
    };

    return validTransitions[from]?.contains(to) ?? false;
  }

  double _calculateAverageResponseTime(
    final List<VoiceCallMessage> messageHistory,
  ) {
    if (messageHistory.length < 2) return 0.0;

    Duration totalResponseTime = Duration.zero;
    int responseCount = 0;

    for (int i = 1; i < messageHistory.length; i++) {
      final current = messageHistory[i];
      final previous = messageHistory[i - 1];

      if (current.isUser != previous.isUser) {
        totalResponseTime += current.timestamp.difference(previous.timestamp);
        responseCount++;
      }
    }

    return responseCount > 0
        ? totalResponseTime.inMilliseconds / responseCount
        : 0.0;
  }

  double _calculateConversationBalance(
    final Duration userTime,
    final Duration aiTime,
  ) {
    if (userTime == Duration.zero && aiTime == Duration.zero) return 0.5;

    final totalTime = userTime + aiTime;
    return totalTime.inMilliseconds > 0
        ? userTime.inMilliseconds / totalTime.inMilliseconds
        : 0.5;
  }

  bool _shouldTimeoutPhase(
    final CallPhase phase,
    final Duration currentDuration,
  ) {
    final timeout = getPhaseTimeoutDuration(phase);
    return timeout != null && currentDuration >= timeout;
  }
}
