/// Interfaz para servicios que necesitan comunicarse con el contexto de chat
/// desde el contexto de llamadas, manteniendo el aislamiento de bounded contexts
abstract interface class IChatIntegrationService {
  /// Obtiene el último mensaje del historial de chat
  /// Retorna null si no hay mensajes
  Future<Map<String, dynamic>?> getLastMessage();

  /// Obtiene una lista de mensajes del historial de chat
  /// [limit] Número máximo de mensajes a obtener
  Future<List<Map<String, dynamic>>> getMessageHistory({final int limit = 10});

  /// Convierte datos de mensaje a formato esperado por el contexto de call
  Map<String, dynamic> convertMessageData(
    final Map<String, dynamic> messageData,
  );
}
