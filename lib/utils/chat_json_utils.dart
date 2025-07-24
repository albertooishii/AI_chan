import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/imported_chat.dart';
import '../constants/app_colors.dart';

/// Muestra un diálogo para pegar JSON manualmente

class ChatJsonUtils {
  /// Guarda un string JSON en un archivo seleccionado por el usuario y retorna éxito o error
  static Future<(bool success, String? error)> saveJsonFile(String jsonStr) async {
    try {
      final unixDate = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final defaultName = 'ai_chan_$unixDate.json';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar chat como JSON',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonStr),
      );
      if (result != null) {
        return (true, null);
      }
      return (false, null);
    } catch (e) {
      return (false, 'Error al guardar archivo:\n${e.toString()}');
    }
  }

  /// Importa perfil y mensajes desde un JSON plano y devuelve un ImportedChat
  static ImportedChat? importAllFromJson(String jsonStr, {void Function(String error)? onError}) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic> ||
          !decoded.containsKey('userName') ||
          !decoded.containsKey('aiName') ||
          !decoded.containsKey('personality') ||
          !decoded.containsKey('biography') ||
          !decoded.containsKey('appearance') ||
          !decoded.containsKey('timeline') ||
          !decoded.containsKey('messages')) {
        onError?.call('Estructura de JSON inválida. Debe tener todos los campos del perfil y mensajes al mismo nivel.');
        return null;
      }
      final imported = ImportedChat.fromJson(decoded);
      if (imported.profile.userName.isEmpty) {
        onError?.call('userName');
        return null;
      } else if (imported.profile.aiName.isEmpty) {
        onError?.call('aiName');
        return null;
      }
      return imported;
    } catch (e) {
      onError?.call(e.toString());
      return null;
    }
  }

  // ...puedes dejar aquí utilidades de UI como pasteJsonDialog y pickJsonFile si las usas en la app...
  static Future<String?> pasteJsonDialog(BuildContext context) async {
    final controller = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Pega el JSON exportado', style: TextStyle(color: Colors.pinkAccent)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Pega aquí el JSON',
            hintStyle: TextStyle(color: AppColors.primary),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar', style: TextStyle(color: AppColors.primary)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('Importar', style: TextStyle(color: AppColors.secondary)),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
          ),
        ],
      ),
    );
  }

  static Future<(String? json, String? error)> pickJsonFile() async {
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
