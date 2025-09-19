import 'package:ai_chan/shared.dart';

/// Interfaz para servicios de TTS nativo específica del dominio core
abstract interface class INativeTtsService implements ITtsService {
  /// Verifica si el TTS nativo está disponible en la plataforma
  Future<bool> isNativeTtsAvailable();

  /// Obtiene voces filtradas por idioma
  Future<List<Map<String, dynamic>>> getVoicesForLanguage(
    final String languageCode,
  );

  /// Filtra voces según códigos de idioma objetivo
  Future<List<Map<String, dynamic>>> filterVoicesByTargetCodes(
    final List<Map<String, dynamic>> voices,
    final List<String> userCodes,
    final List<String> aiCodes,
  );

  /// Detiene la síntesis actual
  Future<bool> stop();

  /// Obtiene idiomas disponibles para descargar
  Future<List<Map<String, dynamic>>> getDownloadableLanguages();

  /// Verifica el estado de descarga de un idioma
  Future<String> getLanguageDownloadStatus(final String languageCode);

  /// Formatea información de voz para mostrar
  String formatVoiceInfo(final Map<String, dynamic> voice);
}
