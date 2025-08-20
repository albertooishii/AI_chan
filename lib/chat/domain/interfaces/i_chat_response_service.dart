/// Chat Response Service - Domain Port
/// Interfaz para la orquestación de respuestas de chat dentro del dominio.
/// Esta capa encapsula la lógica de envío y procesamiento de mensajes de chat.
abstract class IChatResponseService {
  /// Envía mensajes al backend/servicio IA y devuelve una estructura con la
  /// respuesta procesada. El shape del Map puede contener keys como
  /// `assistantMessage`, `images`, `metadata`, etc.
  Future<Map<String, dynamic>> sendChat(
    List<Map<String, dynamic>> messages, {
    Map<String, dynamic>? options,
  });

  /// Opcional: lista de modelos compatibles para usar en la orquestación.
  Future<List<String>> getSupportedModels();
}
