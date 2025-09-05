import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/shared/domain/interfaces/i_file_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:file_picker/file_picker.dart';

/// Use Case que maneja la lógica de import/export de datos de onboarding
/// Extrae toda la lógica de archivos y backup de la UI
class ImportExportOnboardingUseCase {
  final IFileService fileService;

  ImportExportOnboardingUseCase({required this.fileService});

  /// Importa datos desde un archivo JSON
  Future<ImportExportResult> importFromJson() async {
    Log.d('📥 Iniciando importación desde JSON', tag: 'IMPORT_EXPORT_UC');

    try {
      final result = await chat_json_utils.ChatJsonUtils.importJsonFile();
      final String? jsonStr = result.$1;
      final String? error = result.$2;

      if (error != null) {
        return ImportExportResult.error('Error al leer archivo: $error');
      }

      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return ImportExportResult.error(
          'El archivo está vacío o no contiene datos válidos',
        );
      }

      String? importError;
      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (err) => importError = err,
      );

      if (importError != null || imported == null) {
        return ImportExportResult.error(
          'No se pudo importar la biografía: ${importError ?? 'Error desconocido'}',
        );
      }

      Log.d('✅ Importación JSON exitosa', tag: 'IMPORT_EXPORT_UC');
      return ImportExportResult.success(data: imported);
    } catch (e) {
      Log.e('Error durante importación JSON: $e', tag: 'IMPORT_EXPORT_UC');
      return ImportExportResult.error(
        'Error inesperado durante la importación: $e',
      );
    }
  }

  /// Restaura datos desde un backup local (archivo ZIP)
  Future<ImportExportResult> restoreFromLocalBackup() async {
    Log.d(
      '📥 Iniciando restauración desde backup local',
      tag: 'IMPORT_EXPORT_UC',
    );

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        return ImportExportResult.cancelled();
      }

      final path = result.files.first.path;
      if (path == null) {
        return ImportExportResult.error(
          'No se pudo acceder al archivo seleccionado',
        );
      }

      if (!await fileService.fileExists(path)) {
        return ImportExportResult.error('El archivo seleccionado no existe');
      }

      // TODO: Refactorizar BackupService para usar IFileService
      // Por ahora usamos la implementación existente
      final fileData = await fileService.loadFile(path);
      if (fileData == null || fileData.isEmpty) {
        return ImportExportResult.error('El archivo de backup está vacío');
      }

      // Convertir bytes a string para procesar como JSON
      final jsonStr = String.fromCharCodes(fileData);

      if (jsonStr.trim().isEmpty) {
        return ImportExportResult.error(
          'El archivo de backup está vacío o no contiene JSON válido',
        );
      }

      String? importError;
      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (err) => importError = err,
      );

      if (importError != null || imported == null) {
        return ImportExportResult.error(
          'Error al procesar el backup: ${importError ?? 'Formato inválido'}',
        );
      }

      Log.d('✅ Restauración de backup exitosa', tag: 'IMPORT_EXPORT_UC');
      return ImportExportResult.success(data: imported);
    } catch (e) {
      Log.e(
        'Error durante restauración de backup: $e',
        tag: 'IMPORT_EXPORT_UC',
      );
      return ImportExportResult.error(
        'Error inesperado durante la restauración: $e',
      );
    }
  }

  /// Valida si un archivo de backup es válido por su path
  Future<bool> isValidBackupFile(String filePath) async {
    try {
      if (!await fileService.fileExists(filePath)) return false;

      // Intentar leer el archivo para validar
      final fileData = await fileService.loadFile(filePath);
      if (fileData == null || fileData.isEmpty) return false;

      // Por ahora solo validamos que el archivo existe y tiene contenido
      // TODO: Implementar validación más robusta cuando BackupService use IFileService
      return true;
    } catch (e) {
      Log.w('Error validando archivo de backup: $e');
      return false;
    }
  }
}

/// Resultado de operaciones de import/export
class ImportExportResult {
  final bool success;
  final bool cancelled;
  final String? error;
  final ImportedChat? data;

  const ImportExportResult._({
    required this.success,
    required this.cancelled,
    this.error,
    this.data,
  });

  /// Resultado exitoso con datos importados
  factory ImportExportResult.success({required ImportedChat data}) {
    return ImportExportResult._(success: true, cancelled: false, data: data);
  }

  /// Resultado con error
  factory ImportExportResult.error(String message) {
    return ImportExportResult._(
      success: false,
      cancelled: false,
      error: message,
    );
  }

  /// Operación cancelada por el usuario
  factory ImportExportResult.cancelled() {
    return const ImportExportResult._(success: false, cancelled: true);
  }

  /// Indica si la operación fue exitosa
  bool get isSuccess => success;

  /// Indica si hubo un error
  bool get hasError => error != null;

  /// Indica si fue cancelada
  bool get wasCancelled => cancelled;
}
