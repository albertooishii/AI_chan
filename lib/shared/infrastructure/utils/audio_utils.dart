import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/shared/infrastructure/config/config.dart';

/// Devuelve el directorio local de audios forzando el uso del directorio
/// de documentos de la aplicación bajo la carpeta `audio`.
Future<Directory> getLocalAudioDir() async {
  // Test-only override (set via Config.setOverrides({'TEST_AUDIO_DIR': '<path>'}))
  final testOverride = Config.get('TEST_AUDIO_DIR', '');
  if (testOverride.isNotEmpty) {
    final d = Directory(testOverride);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  if (kIsWeb) {
    return Directory('AI_chan_audio');
  }

  final appDoc =
      (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();

  final audioDir = Directory('${appDoc.path}/AI_chan/audio');
  if (!audioDir.existsSync()) audioDir.createSync(recursive: true);
  return audioDir;
}
