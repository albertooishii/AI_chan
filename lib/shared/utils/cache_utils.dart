import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/core/config.dart';

/// Devuelve el directorio local de caché según plataforma usando siempre
/// las rutas recomendadas por el sistema operativo.
Future<Directory> getLocalCacheDir() async {
  // Test-only override (set via Config.setOverrides({'TEST_CACHE_DIR': '<path>'}))
  final testOverride = Config.get('TEST_CACHE_DIR', '');
  if (testOverride.isNotEmpty) {
    final d = Directory(testOverride);
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  if (kIsWeb) {
    return Directory('AI_chan_cache');
  }
  // Prefer tmp directory for cache-like ephemeral files, but place cache
  // inside a dedicated subfolder so files don't get mixed with other tmp
  // data (e.g. /tmp/AI_chan_cache).
  try {
    final tmp = await getTemporaryDirectory();
    final cacheDir = Directory('${tmp.path}${Platform.pathSeparator}AI_chan_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return cacheDir;
  } catch (_) {
    // Fallback to application support directory if tmp not available
    final support = await getApplicationSupportDirectory();
    final cacheDir = Directory('${support.path}${Platform.pathSeparator}AI_chan_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return cacheDir;
  }
}
