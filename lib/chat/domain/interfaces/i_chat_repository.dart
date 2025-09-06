/// Chat Repository - Domain Port
/// Interfaz para persistencia del contexto de chat.
/// Define el contrato para almacenar y recuperar conversaciones de chat.
abstract class IChatRepository {
  /// Guarda el estado completo del chat (profile, messages, events) en formato JSON-serializable.
  Future<void> saveAll(final Map<String, dynamic> exportedJson);

  /// Carga el estado completo del chat desde almacenamiento local. Devuelve null si no hay nada.
  Future<Map<String, dynamic>?> loadAll();

  /// Elimina todo el historial y datos relacionados al chat.
  Future<void> clearAll();

  /// Exporta el chat a JSON (string) a partir del objeto JSON-serializable.
  Future<String> exportAllToJson(final Map<String, dynamic> exportedJson);

  /// Importa un JSON string y devuelve el objeto parsed (o null si falla).
  Future<Map<String, dynamic>?> importAllFromJson(final String jsonStr);
}
