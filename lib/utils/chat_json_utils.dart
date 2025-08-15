import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/imported_chat.dart';
import '../constants/app_colors.dart';
import '../models/ai_chan_profile.dart';

/// Muestra un diálogo para pegar JSON manualmente

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
      if (result != null) {
        return (true, null);
      }
      return (false, null);
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

  // ...puedes dejar aquí utilidades de UI como pasteJsonDialog y pickJsonFile si las usas en la app...
  static Future<void> showExportedJsonDialog(BuildContext context, String json) async {
    return await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Vista previa JSON exportado', style: TextStyle(color: Colors.pinkAccent)),
        content: TextField(
          controller: TextEditingController(text: json),
          maxLines: 20,
          readOnly: true,
          style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            child: const Text('Cerrar', style: TextStyle(color: AppColors.primary)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  static Future<(String? json, String? error)> importJsonFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
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
