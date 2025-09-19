import 'package:ai_chan/shared/ai_providers/core/models/audio/voice_info.dart';

/// Interface for voice providers (AI providers that support TTS)
abstract class TTSVoiceProvider {
  Future<List<VoiceInfo>> getAvailableVoices();
}
