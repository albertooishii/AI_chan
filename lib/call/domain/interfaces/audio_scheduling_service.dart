/// Domain interface for audio playback scheduling strategies
/// Defines the contract for timing-specific playback behavior
abstract interface class AudioSchedulingService {
  /// Schedule audio playback with provider-specific timing and retry logic
  /// [playbackFunction] is the function to execute for audio playback
  void schedulePlayback(final Function playbackFunction);
}
