import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Devuelve el directorio local de audios según plataforma y variables .env
Future<Directory> getLocalAudioDir() async {
  String? configured;
  if (kIsWeb) {
    configured = dotenv.env['AUDIO_DIR_WEB'];
  } else if (Platform.isAndroid) {
    configured = dotenv.env['AUDIO_DIR_ANDROID'];
  } else if (Platform.isIOS) {
    configured = dotenv.env['AUDIO_DIR_IOS'];
  } else {
    // Desktop: always use $HOME/AI_chan/audio dynamically
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isEmpty) throw StateError('No se pudo determinar el home del usuario');
    configured = '\$HOME/AI_chan/audio';
  }

  if (configured == null || configured.trim().isEmpty) {
    throw StateError('AUDIO_DIR no está configurado en .env para esta plataforma');
  }

  final out = Directory(configured.trim());
  if (!await out.exists()) await out.create(recursive: true);
  return out;
}
