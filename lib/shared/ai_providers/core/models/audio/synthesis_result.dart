import 'voice_settings.dart';

/// 🎯 DDD: Resultado de síntesis de voz
class SynthesisResult {
  const SynthesisResult({
    required this.audioData,
    required this.format,
    required this.duration,
    required this.settings,
  });

  final List<int> audioData;
  final String format;
  final Duration duration;
  final VoiceSettings settings;

  @override
  String toString() =>
      'SynthesisResult(${audioData.length} bytes, $format, ${duration.inMilliseconds}ms)';
}
