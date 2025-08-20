import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/config.dart';
import 'package:path_provider/path_provider.dart';

/// Devuelve el directorio local de caché según plataforma
/// Solo permite configuración personalizada en desktop (Windows, macOS, Linux)
/// Para móviles (Android, iOS) siempre usa directorios estándar del sistema
Future<Directory> getLocalCacheDir() async {
  // Solo permitir configuración personalizada en plataformas desktop
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    // Desktop: try env first, otherwise fallback to $HOME/AI_chan/cache
    String configured = Config.get('CACHE_DIR_DESKTOP', '~/AI_chan/cache');

    var cfg = configured.trim();
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';

    if (cfg.startsWith('~')) {
      if (home.isEmpty) {
        throw StateError(
          'No se pudo determinar el home del usuario para expandir ~ en CACHE_DIR',
        );
      }
      cfg = cfg.replaceFirst('~', home);
    }

    // Reemplazar formas comunes de $HOME (literal) por la ruta HOME
    cfg = cfg.replaceAll(r'\$HOME', home);
    cfg = cfg.replaceAll(r'$HOME', home);

    if (!cfg.startsWith('/') && home.isNotEmpty) {
      // Ruta relativa -> interpretarla dentro de $HOME
      cfg = '$home/$cfg';
    }

    final out = Directory(cfg);
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  // Para móviles y web, usar directorio estándar de la aplicación
  return await getApplicationSupportDirectory();
}
