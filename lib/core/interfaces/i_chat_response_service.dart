/// Interfaz para la orquestación de respuestas de chat.
///
/// Esta capa encapsula la lógica que antes vivía en servicios concretos y en
/// `ChatProvider` (selección de modelo, manejo de reintentos, parseo de respuesta,
/// detección de imágenes/acciones). Se mantiene lo más simple posible para la
/// migración inicial: acepta mensajes y devuelve un Map con la respuesta.
abstract class IChatResponseService {
  /// Envía mensajes al backend/servicio IA y devuelve una estructura con la
  /// respuesta procesada. El shape del Map puede contener keys como
  /// `assistantMessage`, `images`, `metadata`, etc.
  Future<Map<String, dynamic>> sendChat(List<Map<String, dynamic>> messages, {Map<String, dynamic>? options});

  /// Opcional: lista de modelos compatibles para usar en la orquestación.
  Future<List<String>> getSupportedModels();
}
