/// Interfaz para representar un mensaje en el contexto de llamadas
/// Abstrae el concepto de mensaje sin depender del bounded context de chat
abstract interface class ICallMessage {
  /// ID único del mensaje
  String get id;

  /// Contenido del mensaje
  String get content;

  /// Autor del mensaje
  String get author;

  /// Timestamp del mensaje
  DateTime get timestamp;

  /// Indica si el mensaje es del usuario
  bool get isUser;

  /// Indica si el mensaje es del asistente
  bool get isAssistant;
}
