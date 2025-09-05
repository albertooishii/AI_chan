import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_language_resolver.dart';
import 'package:ai_chan/shared/domain/interfaces/i_file_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Servicio dedicado para sintetizar TTS y persistir el archivo en el
/// directorio local de audio configurado. Devuelve la ruta final del archivo
/// sintetizado o null si falló.
class TtsService {
  final IAudioChatService audioService;
  final ILanguageResolver languageResolver;
  final IFileService fileService;

  TtsService(this.audioService, this.languageResolver, this.fileService);

  /// Sintetiza `text` usando el audioService y persiste el fichero en la
  /// carpeta local de audio configurada. Devuelve la ruta final o null.
  Future<String?> synthesizeAndPersist(String text, {String voice = 'nova'}) async {
    try {
      // Resolve language code using the injected language resolver
      final lang = await languageResolver.resolveLanguageCode(voice);

      // Resolve preferred voice using PrefsUtils helper
      final preferredVoice = await PrefsUtils.getPreferredVoice(fallback: voice);

      // Synthesize using audio service (returns file path now, not File object)
      final synthesizedPath = await audioService.synthesizeTts(text, voice: preferredVoice, languageCode: lang);

      if (synthesizedPath == null) return null;

      // Get local audio directory
      final localAudioDir = await fileService.getLocalAudioDirectory();

      // If file is already in the correct directory, return it
      if (synthesizedPath.startsWith(localAudioDir)) {
        return synthesizedPath;
      }

      // Otherwise, move it to the local audio directory
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = synthesizedPath.split('.').last;
      final finalPath = '$localAudioDir/assistant_tts_$timestamp.$extension';

      // Load source file and save to destination
      final fileData = await fileService.loadFile(synthesizedPath);
      if (fileData != null) {
        await fileService.saveFile(fileData, 'assistant_tts_$timestamp.$extension', directory: localAudioDir);

        // Try to delete original if it's in a temp location
        try {
          await fileService.deleteFile(synthesizedPath);
        } catch (_) {
          // Ignore errors when deleting temp files
        }

        return finalPath;
      }

      return synthesizedPath; // Fallback to original path
    } catch (e) {
      Log.w('[Audio][TTS] Error in synthesizeAndPersist: $e');
      return null;
    }
  }
}
