/// Interfaz mínima para persistencia del chat.
/// Esta versión usa tipos JSON-compatibles (Map) para minimizar dependencias
/// entre módulos durante la migración.
abstract class IChatRepository {
  /// Guarda el estado completo del chat (profile, messages, events) en formato JSON-serializable.
  Future<void> saveAll(Map<String, dynamic> exportedJson);

  /// Carga el estado completo del chat desde almacenamiento local. Devuelve null si no hay nada.
  Future<Map<String, dynamic>?> loadAll();

  /// Elimina todo el historial y datos relacionados al chat.
  Future<void> clearAll();

  /// Exporta el chat a JSON (string) a partir del objeto JSON-serializable.
  Future<String> exportAllToJson(Map<String, dynamic> exportedJson);

  /// Importa un JSON string y devuelve el objeto parsed (o null si falla).
  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr);
}

// (única definición arriba)
