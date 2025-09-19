import 'dart:io';
import 'dart:convert';

import 'dart:math';
import 'package:ai_chan/shared/infrastructure/utils/image/image_utils.dart'
    as image_utils;
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';

/// Central service to persist images produced by AI providers.
///
/// Responsibilities:
/// - Accept base64 (or data URI) strings, save them as files using the
///   shared `image_utils` implementation and return the stored filename.
/// - Provide a single place to adapt future persistence rules (e.g. S3,
///   alternate storage) without changing provider or application code.
class ImagePersistenceService {
  ImagePersistenceService._();
  static final ImagePersistenceService instance = ImagePersistenceService._();

  /// Save a base64 (or data URI) string as an image file.
  /// Returns the relative filename (not full path) or null on failure.
  /// After saving, callers should discard the base64 (this service does not keep it).
  Future<String?> saveBase64Image(
    final String base64, {
    final String prefix = 'img',
  }) async {
    try {
      if (base64.trim().isEmpty) return null;
      // Generate a UUID-like filename to ensure uniqueness and use .jpg extension
      final fileName = '${_generateUuidV4()}.jpg';
      final result = await image_utils.saveBase64ImageToFile(
        base64,
        prefix: prefix,
        fileName: fileName,
      );
      if (result != null) {
        Log.d('[ImagePersistence] Saved image as $result');
        return result;
      }
      Log.w('[ImagePersistence] saveBase64Image returned null');
      return null;
    } on Exception catch (e) {
      Log.e('[ImagePersistence] Error saving image', error: e);
      return null;
    }
  }

  /// Delete an image file by name (relative filename created by saveBase64ImageToFile).
  /// Returns true if deletion succeeded or file did not exist.
  Future<bool> deleteImage(final String fileName) async {
    try {
      final dir = await image_utils.getLocalImageDir();
      final absPath = '${dir.path}/$fileName';
      final file = File(absPath);
      if (!file.existsSync()) return true;
      await file.delete();
      return true;
    } on Exception catch (e) {
      Log.w('[ImagePersistence] Error deleting image $fileName: $e');
      return false;
    }
  }

  /// Load an image file (previously saved via `saveBase64Image`) and return
  /// its raw base64 content (no data URI prefix). Returns null on failure.
  Future<String?> loadImageAsBase64(final String fileName) async {
    try {
      if (fileName.trim().isEmpty) return null;
      final dir = await image_utils.getLocalImageDir();
      final absPath = '${dir.path}/$fileName';
      final file = File(absPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } on Exception catch (e) {
      Log.w('[ImagePersistence] Error reading image $fileName: $e');
      return null;
    }
  }
}

String _generateUuidV4() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (final _) => rand.nextInt(256));
  // Set the version to 4 -> xxxx-4xxx-yxxx-xxxx
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Set the variant to RFC 4122
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String toHex(final List<int> b) =>
      b.map((final e) => e.toRadixString(16).padLeft(2, '0')).join();

  final hex = toHex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
