/// 🎯 DDD: Interface for tone and sound effects services
/// Domain contract for audio tone generation - SIMPLIFICADA
abstract interface class IToneService {
  /// 📞 Play ringtone/RBT (Ring Back Tone)
  Future<void> playRingtone({
    final int durationMs = 3000,
    final bool cyberpunkStyle = true,
  });

  /// 📵 Play hangup/error tone
  Future<void> playHangupTone({
    final int durationMs = 350,
    final bool cyberpunkStyle = true,
  });

  /// Stop any current playback
  Future<void> stop();

  /// Check if service is available
  Future<bool> isAvailable();
}
