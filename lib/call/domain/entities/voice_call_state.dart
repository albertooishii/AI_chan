enum CallPhase { initializing, ringing, connecting, active, ending, ended }

enum CallType { incoming, outgoing }

enum CallEndReason {
  hangup,
  rejected,
  missed,
  timeout,
  noAnswer,
  error,
  userHangup,
}

class VoiceCallState {
  final CallPhase phase;
  final CallType type;
  final bool isAccepted;
  final bool isMuted;
  final bool hangupInProgress;
  final bool endCallTagReceived;
  final bool startCallTagReceived;
  final bool forceReject;
  final bool userHasAcceptedCall;
  final bool isAISpeaking;
  final bool isUserSpeaking;
  final int callDuration;
  final double soundLevel;
  final String aiText;
  final String userText;
  final String aiLabel;
  final String userLabel;
  final CallEndReason? endReason;
  final String? errorMessage;

  const VoiceCallState({
    this.phase = CallPhase.initializing,
    required this.type,
    this.isAccepted = false,
    this.isMuted = false,
    this.hangupInProgress = false,
    this.endCallTagReceived = false,
    this.startCallTagReceived = false,
    this.forceReject = false,
    this.userHasAcceptedCall = false,
    this.isAISpeaking = false,
    this.isUserSpeaking = false,
    this.callDuration = 0,
    this.soundLevel = 0.0,
    this.aiText = '',
    this.userText = '',
    this.aiLabel = 'IA',
    this.userLabel = 'Tú',
    this.endReason,
    this.errorMessage,
  });

  // Factory constructor for initial state
  factory VoiceCallState.initial({CallType? callType}) {
    return VoiceCallState(type: callType ?? CallType.outgoing);
  }

  // Computed properties para compatibilidad
  bool get isIncoming => type == CallType.incoming;
  bool get canAccept =>
      isIncoming &&
      !isAccepted &&
      phase == CallPhase.ringing &&
      !hangupInProgress;
  bool get canHangup => phase != CallPhase.ended && !hangupInProgress;
  bool get showAcceptButton =>
      isIncoming && !userHasAcceptedCall && phase == CallPhase.ringing;

  VoiceCallState copyWith({
    CallPhase? phase,
    CallType? type,
    bool? isAccepted,
    bool? isMuted,
    bool? hangupInProgress,
    bool? endCallTagReceived,
    bool? startCallTagReceived,
    bool? forceReject,
    bool? userHasAcceptedCall,
    bool? isAISpeaking,
    bool? isUserSpeaking,
    int? callDuration,
    double? soundLevel,
    String? aiText,
    String? userText,
    String? aiLabel,
    String? userLabel,
    CallEndReason? endReason,
    String? errorMessage,
  }) {
    return VoiceCallState(
      phase: phase ?? this.phase,
      type: type ?? this.type,
      isAccepted: isAccepted ?? this.isAccepted,
      isMuted: isMuted ?? this.isMuted,
      hangupInProgress: hangupInProgress ?? this.hangupInProgress,
      endCallTagReceived: endCallTagReceived ?? this.endCallTagReceived,
      startCallTagReceived: startCallTagReceived ?? this.startCallTagReceived,
      forceReject: forceReject ?? this.forceReject,
      userHasAcceptedCall: userHasAcceptedCall ?? this.userHasAcceptedCall,
      isAISpeaking: isAISpeaking ?? this.isAISpeaking,
      isUserSpeaking: isUserSpeaking ?? this.isUserSpeaking,
      callDuration: callDuration ?? this.callDuration,
      soundLevel: soundLevel ?? this.soundLevel,
      aiText: aiText ?? this.aiText,
      userText: userText ?? this.userText,
      aiLabel: aiLabel ?? this.aiLabel,
      userLabel: userLabel ?? this.userLabel,
      endReason: endReason ?? this.endReason,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceCallState &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          type == other.type &&
          isAccepted == other.isAccepted &&
          isMuted == other.isMuted &&
          hangupInProgress == other.hangupInProgress &&
          endCallTagReceived == other.endCallTagReceived &&
          startCallTagReceived == other.startCallTagReceived &&
          forceReject == other.forceReject &&
          userHasAcceptedCall == other.userHasAcceptedCall &&
          isAISpeaking == other.isAISpeaking &&
          isUserSpeaking == other.isUserSpeaking &&
          callDuration == other.callDuration &&
          soundLevel == other.soundLevel &&
          aiText == other.aiText &&
          userText == other.userText &&
          aiLabel == other.aiLabel &&
          userLabel == other.userLabel &&
          endReason == other.endReason &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      phase.hashCode ^
      type.hashCode ^
      isAccepted.hashCode ^
      isMuted.hashCode ^
      hangupInProgress.hashCode ^
      endCallTagReceived.hashCode ^
      startCallTagReceived.hashCode ^
      forceReject.hashCode ^
      userHasAcceptedCall.hashCode ^
      isAISpeaking.hashCode ^
      isUserSpeaking.hashCode ^
      callDuration.hashCode ^
      soundLevel.hashCode ^
      aiText.hashCode ^
      userText.hashCode ^
      aiLabel.hashCode ^
      userLabel.hashCode ^
      endReason.hashCode ^
      errorMessage.hashCode;

  @override
  String toString() {
    return 'VoiceCallState{'
        'phase: $phase, '
        'type: $type, '
        'isAccepted: $isAccepted, '
        'isMuted: $isMuted, '
        'hangupInProgress: $hangupInProgress, '
        'userHasAcceptedCall: $userHasAcceptedCall, '
        'isAISpeaking: $isAISpeaking, '
        'isUserSpeaking: $isUserSpeaking, '
        'callDuration: $callDuration, '
        'soundLevel: $soundLevel, '
        'endReason: $endReason'
        '}';
  }
}
