/// Servicio para procesar y limpiar texto de mensajes
/// Maneja la eliminación de contenido de llamadas y caracteres de escape
class MessageTextProcessorService {
  /// Limpia el texto de un mensaje eliminando caracteres de escape y contenido de llamadas
  static String cleanMessageText(String text) {
    String cleaned = text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
    cleaned = cleaned.replaceAll(RegExp(r'\\(?!n|\")'), '');
    cleaned = cleaned.replaceAll(r'\\', '');

    // Remover contenido entre [call] y [/call] si existe
    if (cleaned.contains('[call]') && cleaned.contains('[/call]')) {
      cleaned = cleaned.replaceAll(
        RegExp(r'\[call\].*?\[\/call\]', dotAll: true),
        '',
      );
    }

    return cleaned;
  }

  /// Formatea la hora de un mensaje para mostrar en la UI
  static String formatMessageTime(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  /// Colapsa espacios múltiples en un texto y elimina espacios al inicio y final
  static String collapseWhitespace(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
