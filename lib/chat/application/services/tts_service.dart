import 'dart:io';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_language_resolver.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/audio_utils.dart' as audio_utils;

/// Servicio dedicado para sintetizar TTS y persistir el archivo en el
/// directorio local de audio configurado. Devuelve la ruta final del archivo
/// sintetizado o null si falló.
class TtsService {
  final IAudioChatService audioService;
  final ILanguageResolver languageResolver;
  final Future<Directory> Function()? _localAudioDirGetter;

  /// [localAudioDirGetter] permite inyectar un getter de directorio en tests
  /// para evitar depender de variables de entorno o dotenv no inicializado.
  TtsService(
    this.audioService,
    this.languageResolver, {
    Future<Directory> Function()? localAudioDirGetter,
  }) : _localAudioDirGetter = localAudioDirGetter;

  /// Sintetiza `text` usando el audioService y persiste el fichero en la
  /// carpeta local de audio configurada. Devuelve la ruta final o null.
  Future<String?> synthesizeAndPersist(
    String text, {
    String voice = 'nova',
  }) async {
    // Resolve language code using the injected language resolver
    final lang = await languageResolver.resolveLanguageCode(voice);

    // Resolve preferred voice using PrefsUtils helper
    final preferredVoice = await PrefsUtils.getPreferredVoice(fallback: voice);

    final file = await audioService.synthesizeTts(
      text,
      voice: preferredVoice,
      languageCode: lang,
    );
    if (file == null) return null;

    try {
      final localDir =
          await (_localAudioDirGetter?.call() ??
              audio_utils.getLocalAudioDir());
      String finalPath = file.path;
      if (!file.path.startsWith(localDir.path)) {
        final ext = file.path.split('.').last;
        final dest =
            '${localDir.path}/assistant_tts_${DateTime.now().millisecondsSinceEpoch}.$ext';
        try {
          await file.rename(dest);
          finalPath = dest;
        } catch (e) {
          try {
            await file.copy(dest);
            final srcLen = await file.length();
            final dstLen = await File(dest).length();
            if (srcLen == dstLen) {
              try {
                await file.delete();
              } catch (_) {}
            }
            finalPath = dest;
          } catch (e2) {
            Log.w(
              '[Audio][TTS] Could not move synthesized file to local audio dir: $e2',
            );
          }
        }
      }
      return finalPath;
    } catch (e) {
      Log.w('[Audio][TTS] Error persisting synthesized file: $e');
      return file.path;
    }
  }
}
