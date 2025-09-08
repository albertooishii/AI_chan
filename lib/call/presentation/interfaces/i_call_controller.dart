/// 🎯 **Call Controller Interface** - Domain Contract
///
/// Define the contract for main call operations without
/// depending on specific UI framework implementation.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No Flutter dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class ICallController {
  // State getters
  dynamic get currentPhase; // CallPhase enum
  bool get isCallActive;
  bool get isMuted;
  bool get isAiSpeaking;
  bool get isUserTurn;
  Duration get callDuration;
  String get connectionQuality;
  List<dynamic> get messageHistory; // VoiceCallMessage list

  // Core operations
  Future<void> initialize();
  Future<void> startCall();
  Future<void> endCall();
  Future<void> toggleMute();
  Future<void> sendMessage(final String content);
  void updateCallDuration(final Duration duration);
  void dispose();
}
