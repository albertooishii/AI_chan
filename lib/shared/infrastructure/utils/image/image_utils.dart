import 'dart:io';
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/shared/infrastructure/config/config.dart';
import 'package:image/image.dart' as img;
import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart';
import 'package:ai_chan/shared/domain/models/index.dart';

/// Guarda una imagen en base64 en el directorio de documentos de la app
/// bajo la carpeta `images`. Comprime la imagen usando JPEG con 90% de calidad
/// para reducir significativamente el tamaño del archivo.
Future<String?> saveBase64ImageToFile(
  final String base64, {
  final String prefix = 'img',
  final String? fileName,
}) async {
  try {
    // Normalize possible data URIs: if the input is like `data:image/png;base64,AAA...`
    // strip the prefix so we decode only the raw base64 payload. If the input
    // is already raw base64, this is a no-op.
    String normalized = base64.trim();
    bool normalizedApplied = false;
    if (normalized.startsWith('data:')) {
      final idx = normalized.indexOf('base64,');
      if (idx != -1 && idx + 7 < normalized.length) {
        normalized = normalized.substring(idx + 7);
        normalizedApplied = true;
      } else {
        final comma = normalized.indexOf(',');
        if (comma != -1 && comma + 1 < normalized.length) {
          normalized = normalized.substring(comma + 1);
          normalizedApplied = true;
        }
      }
    }

    if (normalizedApplied) {
      Log.d('[Image] Normalized data URI to raw base64', tag: 'IMAGE_UTILS');
    }

    late final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(normalized));
    } on FormatException catch (e) {
      Log.w(
        '[Image] Provided string is not valid base64: $e',
        tag: 'IMAGE_UTILS',
      );
      return null;
    }

    Log.d(
      '[Image] Procesando imagen para compresión JPEG...',
      tag: 'IMAGE_UTILS',
    );

    // Intentar decodificar la imagen original (puede ser PNG, JPEG, etc.)
    img.Image? originalImage;
    try {
      originalImage = img.decodeImage(bytes);
    } on Exception catch (e) {
      Log.w(
        '[Image] Error decodificando imagen, intentando guardar como está: $e',
        tag: 'IMAGE_UTILS',
      );
      // Si falla la decodificación, guardar la imagen tal como está (fallback para tests o imágenes corruptas)
      final finalFileName =
          fileName ?? '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
      final absDir = await getLocalImageDir();
      final absFilePath = '${absDir.path}/$finalFileName';
      final file = await File(absFilePath).writeAsBytes(bytes);
      if (file.existsSync()) {
        Log.i(
          '[Image] Imagen guardada sin compresión en: $absFilePath',
          tag: 'IMAGE_UTILS',
        );
        return finalFileName;
      }
      return null;
    }

    if (originalImage == null) {
      Log.w(
        '[Image] No se pudo decodificar la imagen base64',
        tag: 'IMAGE_UTILS',
      );
      return null;
    }

    // Convertir a JPEG con 90% de calidad para reducir tamaño
    final jpegBytes = img.encodeJpg(originalImage, quality: 90);
    final finalFileName =
        fileName ?? '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final absDir = await getLocalImageDir();
    final absFilePath = '${absDir.path}/$finalFileName';

    Log.d(
      '[Image] Guardando imagen comprimida en: $absFilePath',
      tag: 'IMAGE_UTILS',
    );
    Log.d(
      '[Image] Tamaño original: ${bytes.length} bytes, comprimido: ${jpegBytes.length} bytes',
      tag: 'IMAGE_UTILS',
    );

    final file = await File(absFilePath).writeAsBytes(jpegBytes);
    final exists = file.existsSync();
    if (exists) {
      final reduction = ((bytes.length - jpegBytes.length) / bytes.length * 100)
          .toStringAsFixed(1);
      Log.i(
        '[Image] Imagen guardada correctamente en: $absFilePath (reducción: $reduction%)',
        tag: 'IMAGE_UTILS',
      );
      return finalFileName;
    } else {
      Log.w(
        '[Image] Error: El archivo no existe tras guardar.',
        tag: 'IMAGE_UTILS',
      );
      return null;
    }
  } on Exception catch (e) {
    final isExpected = e is StateError || e is FormatException;
    if (isExpected) {
      Log.w(
        '[Image] No se pudo guardar imagen (esperado): ${e.toString()}',
        tag: 'IMAGE_UTILS',
      );
    } else {
      Log.e('[Image] Error al guardar imagen', tag: 'IMAGE_UTILS', error: e);
    }
    return null;
  }
}

/// Devuelve el directorio local para imágenes: app_documents/images
Future<Directory> getLocalImageDir() async {
  // Allow tests to override the image directory using a test-only key.
  final testOverride = Config.get('TEST_IMAGE_DIR', '').trim();
  if (testOverride.isNotEmpty) {
    final dir = Directory(testOverride);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  if (kIsWeb) {
    // En web no hay un directorio real; usar carpeta virtual en memoria o nombre simbólico.
    return Directory('AI_chan_images');
  }

  // Prefer OS-specific Application Support on desktop so the app doesn't
  // create loose folders under the user's Documents directory. On mobile
  // and web keep using the documents directory (mobile uses app-private
  // Documents; web uses virtual folder name).
  final appDoc =
      (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();

  final imagesDir = Directory('${appDoc.path}/AI_chan/images');
  if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
  return imagesDir;
}

/// Ruta relativa usada internamente para presentar/serializar paths (simple nombre)
Future<String> getRelativeImageDir() async {
  return 'AI_chan/images';
}

// -------------------------
// Profile / avatar helpers
// -------------------------
/// Adds or replaces an avatar in the controller's profile and persists it.
Future<void> addAvatarAndPersist(
  final IChatController chatController,
  final AiImage avatar, {
  final bool replace = false,
}) async {
  try {
    final currentProfile = chatController.profile;
    if (currentProfile == null) return;

    AiChanProfile updatedProfile;
    if (replace) {
      updatedProfile = currentProfile.copyWith(avatars: [avatar]);
    } else {
      updatedProfile = currentProfile.copyWith(
        avatars: [...(currentProfile.avatars ?? []), avatar],
      );
    }

    chatController.dataController.updateProfile(updatedProfile);
  } on Exception catch (_) {
    // Silent as before
  }
}

/// Removes an AiImage (if non-null) from the controller's profile and persists it.
Future<void> removeImageFromProfileAndPersist(
  final IChatController chatController,
  final AiImage? deleted,
) async {
  if (deleted == null) return;
  try {
    final currentProfile = chatController.profile;
    if (currentProfile == null) return;

    final avatars = List<AiImage>.from(currentProfile.avatars ?? []);
    avatars.removeWhere(
      (final a) => a.seed == deleted.seed || a.url == deleted.url,
    );
    final updated = currentProfile.copyWith(avatars: avatars);

    chatController.dataController.updateProfile(updated);
  } on Exception catch (_) {
    // Silent
  }
}
