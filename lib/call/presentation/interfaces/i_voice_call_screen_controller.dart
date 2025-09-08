/// 🎯 **Voice Call Screen Controller Interface** - Domain Contract
///
/// Define the contract for voice call screen operations without
/// depending on specific UI framework implementation.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No Flutter dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class IVoiceCallScreenController {
  // State getters
  dynamic get state; // VoiceCallState
  bool get isIncoming;
  bool get canAccept;
  bool get canHangup;
  bool get showAcceptButton;

  // Core operations
  Future<void> acceptCall();
  Future<void> hangupCall();
  Future<void> startOutgoingCall();
  void updateConnectionState(final String quality);
  void dispose();
}
