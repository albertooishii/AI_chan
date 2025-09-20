import 'package:ai_chan/shared.dart';
import 'package:ai_chan/onboarding/domain/interfaces/i_file_picker_service.dart';

/// Use Case que maneja la lógica de import/export de datos de onboarding
/// Extrae toda la lógica de archivos y backup de la UI
class ImportExportOnboardingUseCase {
  ImportExportOnboardingUseCase({
    final IFileService? fileService,
    required final IFilePickerService filePickerService,
  }) : fileService = fileService ?? getFileService();

  final IFileService fileService;

  /// Importa datos desde un archivo JSON
  Future<ImportExportResult> importFromJson() async {
    Log.d('📥 Iniciando importación desde JSON', tag: 'IMPORT_EXPORT_UC');

    try {
      final result = await ChatJsonUtils.importJsonFile();
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
      final imported = await ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (final err) => importError = err,
      );

      if (importError != null || imported == null) {
        return ImportExportResult.error(
          'No se pudo importar la biografía: ${importError ?? 'Error desconocido'}',
        );
      }

      Log.d('✅ Importación JSON exitosa', tag: 'IMPORT_EXPORT_UC');
      return ImportExportResult.success(data: imported);
    } on Exception catch (e) {
      Log.e('Error durante importación JSON: $e', tag: 'IMPORT_EXPORT_UC');
      return ImportExportResult.error(
        'Error inesperado durante la importación: $e',
      );
    }
  }
}

/// Resultado de operaciones de import/export
class ImportExportResult {
  const ImportExportResult._({
    required this.success,
    required this.cancelled,
    this.error,
    this.data,
  });

  /// Resultado exitoso con datos importados
  factory ImportExportResult.success({required final ChatExport data}) {
    return ImportExportResult._(success: true, cancelled: false, data: data);
  }

  /// Resultado con error
  factory ImportExportResult.error(final String message) {
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
  final bool success;
  final bool cancelled;
  final String? error;
  final ChatExport? data;

  /// Indica si la operación fue exitosa
  bool get isSuccess => success;

  /// Indica si hubo un error
  bool get hasError => error != null;

  /// Indica si fue cancelada
  bool get wasCancelled => cancelled;
}
