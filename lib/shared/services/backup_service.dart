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
  /// Crea un archivo de backup con JSON y media files
  static Future<Archive> _createBackupArchive(final String jsonStr) async {
    final archive = Archive();
    // Add the main JSON as backup.json
    archive.addFile(ArchiveFile.string('backup.json', jsonStr));

    // Add images
    try {
      final imgDir = await image_utils.getLocalImageDir();
      if (await imgDir.exists()) {
        final files = imgDir.listSync().whereType<File>();
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
        final files = aDir.listSync().whereType<File>();
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

    return archive;
  }

  /// Crea un backup local y devuelve el archivo guardado.
  /// Usado para backups automáticos y archivos temporales.
  static Future<File> createLocalBackup({
    required final String jsonStr,
    final String? destinationDirPath,
  }) async {
    final safeTs = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final filename = 'ai_chan_backup_$safeTs.zip';

    final archive = await _createBackupArchive(jsonStr);

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

  /// Crea un backup local en la ruta específica proporcionada por el usuario.
  /// Usado cuando el usuario elige manualmente dónde guardar el archivo.
  static Future<File> createLocalBackupAt({
    required final String jsonStr,
    required final String outputPath,
  }) async {
    final archive = await _createBackupArchive(jsonStr);

    // Asegurar que el path tenga extensión .zip
    var finalPath = outputPath;
    if (!finalPath.toLowerCase().endsWith('.zip')) {
      finalPath = '$finalPath.zip';
    }

    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive);
    final out = File(finalPath);
    await out.writeAsBytes(zipData, flush: true);
    return out;
  }

  /// Restaura desde un archivo de backup (.zip/.gz/plain) y devuelve el JSON
  /// extraído; la importación al estado de la app corre a cargo del llamador.
  static Future<String> restoreAndExtractJson(final String backupPath) async {
    final jsonStr = await extractJsonAndRestoreMedia(backupPath);
    return jsonStr;
  }

  /// Extrae el JSON y restaura ficheros media (images/ y audio/) en los
  /// directorios habituales del sistema de archivos. Devuelve el contenido
  /// JSON extraído (throw en error).
  static Future<String> extractJsonAndRestoreMedia(
    final String backupPath,
  ) async {
    final backupFile = File(backupPath);
    final bytes = await backupFile.readAsBytes();
    if (backupPath.toLowerCase().endsWith('.zip')) {
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
      final decompressed = const GZipDecoder().decodeBytes(bytes);
      final jsonStr = utf8.decode(decompressed);
      return jsonStr;
    } else {
      // Try to parse as plain JSON
      final maybe = utf8.decode(bytes);
      return maybe;
    }
  }
}
