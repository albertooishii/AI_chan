/// Utilidades para servicios de IA (OpenAI, Gemini, etc.)
class AIServiceUtils {
  /// Determina si un código de error es relacionado con cuotas/límites
  static bool isQuotaLike(final int code, final String body) {
    if (code == 400 || code == 403 || code == 429) return true;
    return false;
  }

  /// Determina si un error es temporal y puede ser reintentado
  static bool isRetryableError(final int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  /// Extrae el mensaje de error de una respuesta de API
  static String extractErrorMessage(final String responseBody) {
    try {
      // Implementar lógica común para extraer mensajes de error
      return 'Error en el servicio de IA';
    } on Exception catch (_) {
      return 'Error desconocido en el servicio';
    }
  }
}
