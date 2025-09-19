import 'package:ai_chan/shared.dart';

/// Chat Repository - Domain Port
/// Interfaz para persistencia del contexto de chat.
/// Define el contrato para almacenar y recuperar conversaciones de chat.
abstract class IChatRepository extends ISharedChatRepository {
  // IChatRepository extends ISharedChatRepository to maintain compatibility
  // while allowing shared usage across contexts
}
