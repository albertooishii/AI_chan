import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_language_resolver.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_preferences_service.dart';
import 'package:ai_chan/shared.dart';

/// Servicio dedicado para sintetizar TTS y persistir el archivo en el
/// directorio local de audio configurado. Devuelve la ruta final del archivo
/// sintetizado o null si falló.
class TtsService {
  TtsService(
    this.audioService,
    this.languageResolver,
    this.fileService,
    this.preferencesService,
  );
  final IAudioChatService audioService;
  final ILanguageResolver languageResolver;
  final IFileService fileService;
  final IChatPreferencesService preferencesService;

  /// Sintetiza `text` usando el audioService y persiste el fichero en la
  /// carpeta local de audio configurada. Devuelve la ruta final o null.
  Future<String?> synthesizeAndPersist(
    final String text, {
    final String voice = '', // Dinámico del provider configurado
  }) async {
    try {
      // Resolve language code using the injected language resolver
      final lang = await languageResolver.resolveLanguageCode(voice);

      // Synthesize using audio service (returns file path now, not File object)
      final synthesizedPath = await audioService.synthesizeTts(
        text,
        languageCode: lang,
      );

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
        await fileService.saveFile(
          fileData,
          'assistant_tts_$timestamp.$extension',
          directory: localAudioDir,
        );

        // Try to delete original if it's in a temp location
        try {
          await fileService.deleteFile(synthesizedPath);
        } on Exception catch (_) {}

        return finalPath;
      }

      return synthesizedPath; // Fallback to original path
    } on Exception catch (e) {
      Log.e(
        '[Audio][TTS] Error in synthesizeAndPersist: $e',
        tag: 'TTS',
        error: e,
      );
      return null;
    }
  }
}
