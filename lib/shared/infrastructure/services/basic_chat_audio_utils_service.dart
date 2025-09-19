import 'package:ai_chan/chat/domain/interfaces/i_chat_audio_utils_service.dart';
import 'package:ai_chan/shared/infrastructure/utils/audio_duration_utils.dart';

/// Basic implementation of IChatAudioUtilsService for dependency injection
class BasicChatAudioUtilsService implements IChatAudioUtilsService {
  @override
  Future<Duration?> getAudioDuration(final String filePath) async {
    try {
      return await AudioDurationUtils.getAudioDuration(filePath);
    } on Exception catch (_) {
      // Return null on error to match interface contract
      return null;
    }
  }

  @override
  String formatDuration(final Duration duration) {
    // Format duration as MM:SS
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  bool isValidAudioFormat(final String filePath) {
    // Basic implementation - accept common formats
    final extension = filePath.split('.').last.toLowerCase();
    return ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'].contains(extension);
  }
}
