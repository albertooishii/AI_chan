import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/core/models.dart';
import '../constants/app_colors.dart';

/// Utilities to export/import chat JSON and show a preview dialog with copy/save actions.
class ChatJsonUtils {
  /// Guarda un ImportedChat en un archivo seleccionado por el usuario y retorna éxito o error
  static Future<(bool success, String? error)> saveJsonFile(ImportedChat chat) async {
    try {
      final map = chat.toJson();
      final encoder = JsonEncoder.withIndent('  ');
      final exportStr = encoder.convert(map);
      final unixDate = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final defaultName = 'ai_chan_$unixDate.json';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar chat como JSON',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(exportStr),
      );
      if (result == null) return (false, null); // usuario canceló

      // Asegurar extensión .json
      var path = result;
      if (!path.toLowerCase().endsWith('.json')) {
        path = '$path.json';
      }

      // En Android, FilePicker puede devolver rutas SAF/content (p.ej. '/document/primary:Download/...')
      // Esas rutas no son accesibles mediante dart:io File. Si detectamos ese caso, asumimos que
      // FilePicker ya escribió los bytes correctamente y retornamos éxito.
      if (!kIsWeb && Platform.isAndroid) {
        final lower = path.toLowerCase();
        if (lower.startsWith('/document') || lower.startsWith('content://') || lower.contains('primary:')) {
          // No intentar abrir con File(path) porque fallará con PathNotFoundException.
          return (true, null);
        }
      }

      // Algunos entornos (Linux / desktop) pueden ignorar 'bytes'; escribimos manualmente
      try {
        // En Android moderno puede ser necesario solicitar permisos adicionales para rutas filesystem
        if (!kIsWeb && Platform.isAndroid) {
          try {
            final status = await Permission.manageExternalStorage.status;
            if (!status.isGranted) {
              final req = await Permission.manageExternalStorage.request();
              if (!req.isGranted) {
                final storageReq = await Permission.storage.request();
                if (!storageReq.isGranted) {
                  return (false, 'Permiso de almacenamiento denegado. Habilítalo en ajustes para guardar archivos.');
                }
              }
            }
          } catch (_) {
            final storageReq = await Permission.storage.request();
            if (!storageReq.isGranted) {
              return (false, 'Permiso de almacenamiento denegado. Habilítalo en ajustes para guardar archivos.');
            }
          }
        }

        final file = File(path);
        await file.writeAsString(exportStr);
        final exists = await file.exists();
        if (!exists) return (false, 'No se pudo crear el archivo en: $path');
        final length = await file.length();
        if (length == 0) return (false, 'Archivo creado vacío en: $path');
      } catch (e) {
        // Proveer mensaje más útil en Android
        if (!kIsWeb && Platform.isAndroid) {
          return (false, 'Error escribiendo archivo en Android. Comprueba permisos y el almacenamiento:\n$e');
        }
        return (false, 'Error escribiendo archivo en disco:\n$e');
      }
      return (true, null);
    } catch (e) {
      return (false, 'Error al guardar archivo:\n${e.toString()}');
    }
  }

  /// Importa perfil y mensajes desde un JSON plano y devuelve un ImportedChat (async)
  static Future<ImportedChat?> importAllFromJson(String jsonStr, {void Function(String error)? onError}) async {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic> ||
          !decoded.containsKey('userName') ||
          !decoded.containsKey('aiName') ||
          !decoded.containsKey('biography') ||
          !decoded.containsKey('appearance') ||
          !decoded.containsKey('timeline') ||
          !decoded.containsKey('messages')) {
        onError?.call('Estructura de JSON inválida. Debe tener todos los campos del perfil y mensajes al mismo nivel.');
        return null;
      }
      final imported = ImportedChat.fromJson(decoded);
      final profile = imported.profile;
      AiChanProfile updatedProfile = profile;
      final result = ImportedChat(profile: updatedProfile, messages: imported.messages, events: imported.events);
      if (result.profile.userName.isEmpty) {
        onError?.call('userName');
        return null;
      } else if (result.profile.aiName.isEmpty) {
        onError?.call('aiName');
        return null;
      }
      return result;
    } catch (e) {
      onError?.call(e.toString());
      return null;
    }
  }

  /// Muestra un diálogo con la vista previa del JSON (formateado). Permite copiar o guardar.
  /// Si se pasa [chat], el guardado usará la representación de modelo (evita reserializar en el caller).
  static Future<void> showExportedJsonDialog(BuildContext context, String json, {ImportedChat? chat}) async {
    String preview = json;
    try {
      final decoded = jsonDecode(json);
      preview = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      // Si no se puede parsear, usar el JSON tal como viene
      preview = json;
    }

    return await showAppDialog<void>(
      context: context,
      builder: (ctx) {
        final previewScrollController = ScrollController();
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            'Vista previa JSON exportado',
            style: TextStyle(color: AppColors.secondary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width * 0.8, // 80% del ancho de la pantalla
            height: MediaQuery.of(ctx).size.height * 0.7, // 70% de la altura de la pantalla
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Contenido del archivo JSON:',
                    style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Scrollbar(
                      controller: previewScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: previewScrollController,
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          preview,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontFamily: 'Courier',
                            height: 1.4,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Guardar como...', style: TextStyle(color: AppColors.secondary)),
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (chat != null) {
                  final (success, error) = await ChatJsonUtils.saveJsonFile(chat);
                  if (error != null) {
                    showErrorDialog(error);
                  } else if (success) {
                    showAppSnackBar('Archivo guardado correctamente.', preferRootMessenger: true);
                  }
                } else {
                  try {
                    final unixDate = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                    final defaultName = 'ai_chan_$unixDate.json';
                    final result = await FilePicker.platform.saveFile(
                      dialogTitle: 'Guardar chat como JSON',
                      fileName: defaultName,
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                      bytes: utf8.encode(preview),
                    );
                    if (result == null) return; // cancelado
                    var path = result;
                    if (!path.toLowerCase().endsWith('.json')) path = '$path.json';

                    // Si estamos en Android y la ruta parece ser SAF/content URI, no intentar usar File(path)
                    if (!kIsWeb && Platform.isAndroid) {
                      final lower = path.toLowerCase();
                      if (lower.startsWith('/document') ||
                          lower.startsWith('content://') ||
                          lower.contains('primary:')) {
                        // Confiar en que FilePicker guardó los bytes correctamente
                        showAppSnackBar('Archivo guardado correctamente.', preferRootMessenger: true);
                        return;
                      }
                    }

                    try {
                      final file = File(path);
                      await file.writeAsString(preview);
                      final exists = await file.exists();
                      if (!exists) {
                        showErrorDialog('No se pudo crear el archivo en: $path');
                      } else {
                        showAppSnackBar('Archivo guardado correctamente.', preferRootMessenger: true);
                      }
                    } catch (e) {
                      showErrorDialog('Error guardando archivo:\n${e.toString()}');
                    }
                  } catch (e) {
                    showErrorDialog('Error guardando archivo:\n${e.toString()}');
                  }
                }
              },
            ),
            TextButton(
              child: const Text('Copiar', style: TextStyle(color: AppColors.primary)),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: preview));
                showAppSnackBar('JSON copiado al portapapeles', preferRootMessenger: true);
              },
            ),
            TextButton(
              child: const Text('Cerrar', style: TextStyle(color: AppColors.primary)),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  }

  static Future<(String? json, String? error)> importJsonFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        return (await file.readAsString(), null);
      }
    } catch (e) {
      return (null, 'Error al leer archivo:\n${e.toString()}');
    }
    return (null, null);
  }
}
