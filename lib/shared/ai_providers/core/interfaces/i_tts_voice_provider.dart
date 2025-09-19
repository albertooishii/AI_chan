import 'package:ai_chan/shared.dart';

/// Interface for voice providers (AI providers that support TTS)
abstract class TTSVoiceProvider {
  Future<List<VoiceInfo>> getAvailableVoices();
}
