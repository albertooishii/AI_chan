import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
// No direct dependency on ChatProvider anymore.
import 'package:ai_chan/shared/utils/image_utils.dart' as image_utils;
import 'package:ai_chan/shared/utils/audio_utils.dart' as audio_utils;
import 'package:archive/archive_io.dart';
// test-only overrides are exposed via Config in helpers; no direct import needed here

/// Servicio simple de backup local.
/// - Crea un archivo ZIP que incluye el JSON de backup (el llamador debe
///   proporcionar el JSON ya serializado) y los media (images/, audio/).
/// - Restaura un backup y devuelve el JSON extraído; la importación al estado
///   de la app corre a cargo del llamador.
class BackupService {
  /// Crea un backup local y devuelve el archivo guardado.
  static Future<File> createLocalBackup({
    required String jsonStr,
    String? destinationDirPath,
  }) async {
    // By default create a ZIP including JSON + media. Caller must provide JSON.
    final safeTs = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final filename = 'ai_chan_backup_$safeTs.zip';

    final archive = Archive();
    // Add the main JSON as backup.json
    archive.addFile(ArchiveFile.string('backup.json', jsonStr));

    // Add images
    try {
      final imgDir = await image_utils.getLocalImageDir();
      if (await imgDir.exists()) {
        final files = imgDir.listSync(recursive: false).whereType<File>();
        for (final f in files) {
          try {
            final bytes = f.readAsBytesSync();
            final name = f.uri.pathSegments.isNotEmpty
                ? f.uri.pathSegments.last
                : f.path;
            archive.addFile(ArchiveFile('images/$name', bytes.length, bytes));
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Add audio
    try {
      final aDir = await audio_utils.getLocalAudioDir();
      if (await aDir.exists()) {
        final files = aDir.listSync(recursive: false).whereType<File>();
        for (final f in files) {
          try {
            final bytes = f.readAsBytesSync();
            final name = f.uri.pathSegments.isNotEmpty
                ? f.uri.pathSegments.last
                : f.path;
            archive.addFile(ArchiveFile('audio/$name', bytes.length, bytes));
          } catch (_) {}
        }
      }
    } catch (_) {}

    // If a destination directory path was provided by the user, use it.
    String outPath;
    if (destinationDirPath != null && destinationDirPath.trim().isNotEmpty) {
      final destDir = Directory(destinationDirPath);
      if (!await destDir.exists()) await destDir.create(recursive: true);
      outPath = '${destDir.path}/$filename';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      outPath = '${dir.path}/$filename';
    }
    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive);
    final out = File(outPath);
    await out.writeAsBytes(zipData, flush: true);
    return out;
  }

  /// Restaura desde un archivo de backup (.zip/.gz/plain) y devuelve el JSON
  /// extraído; la importación al estado de la app corre a cargo del llamador.
  static Future<String> restoreAndExtractJson(File backupFile) async {
    final jsonStr = await extractJsonAndRestoreMedia(backupFile);
    return jsonStr;
  }

  /// Extrae el JSON y restaura ficheros media (images/ y audio/) en los
  /// directorios habituales del sistema de archivos. Devuelve el contenido
  /// JSON extraído (throw en error).
  static Future<String> extractJsonAndRestoreMedia(File backupFile) async {
    final bytes = await backupFile.readAsBytes();
    if (backupFile.path.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? jsonStr;
      // Prepare target dirs
      final imgDir = await image_utils.getLocalImageDir();
      final aDir = await audio_utils.getLocalAudioDir();
      if (!await imgDir.exists()) await imgDir.create(recursive: true);
      if (!await aDir.exists()) await aDir.create(recursive: true);

      for (final file in archive) {
        if (file.isFile) {
          final name = file.name;
          if (name == 'backup.json') {
            final content = file.content as List<int>;
            jsonStr = utf8.decode(content);
          } else if (name.startsWith('images/')) {
            final rel = name.substring('images/'.length);
            try {
              final outFile = File('${imgDir.path}/$rel');
              await outFile.writeAsBytes(file.content as List<int>);
            } catch (_) {}
          } else if (name.startsWith('audio/')) {
            final rel = name.substring('audio/'.length);
            try {
              final outFile = File('${aDir.path}/$rel');
              await outFile.writeAsBytes(file.content as List<int>);
            } catch (_) {}
          }
        }
      }
      if (jsonStr == null) {
        throw StateError('backup.json no encontrado en el ZIP');
      }
      return jsonStr;
    } else if (backupFile.path.toLowerCase().endsWith('.gz')) {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      final jsonStr = utf8.decode(decompressed);
      return jsonStr;
    } else {
      // Try to parse as plain JSON
      final maybe = utf8.decode(bytes);
      return maybe;
    }
  }
}
