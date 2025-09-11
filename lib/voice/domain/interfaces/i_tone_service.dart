/// 🎯 DDD: Interface for tone and sound effects services
/// Domain contract for audio tone generation
abstract interface class IToneService {
  /// Play hangup or error tone
  Future<void> playHangupOrErrorTone({
    final int sampleRate = 24000,
    final int durationMs = 350,
    final String preset = 'melodic',
  });

  /// Play custom tone
  Future<void> playCustomTone({
    required final double frequency,
    required final int durationMs,
    final double volume = 1.0,
  });

  /// Play frequency sweep
  Future<void> playFrequencySweep({
    required final double startFreq,
    required final double endFreq,
    required final int durationMs,
    final double volume = 1.0,
  });

  /// Stop any current playback
  Future<void> stop();

  /// Check if service is available
  Future<bool> isAvailable();

  /// Generate ringback tone WAV data
  Future<List<int>> generateRingbackTone({
    final int sampleRate = 44100,
    final double durationSeconds = 2.5,
    final double tempoBpm = 130.0,
    final String preset = 'cyberpunk',
  });

  /// Generate ringtone WAV data
  Future<List<int>> generateRingtone({
    final int sampleRate = 44100,
    final double durationSeconds = 2.5,
    final String preset = 'melodic',
    final bool stereo = true,
  });
}
