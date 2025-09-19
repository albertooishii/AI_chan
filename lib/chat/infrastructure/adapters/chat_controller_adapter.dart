import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart';
import 'package:ai_chan/shared/domain/models/index.dart';

/// Implementación básica de IChatController para infraestructura
/// Esta es principalmente un stub para cumplir con el patrón Port-Adapter
/// La implementación real está en presentation/controllers/chat_controller.dart
class ChatControllerAdapter implements IChatController {
  final List<Message> _messages = [];
  AiChanProfile? _profile;

  @override
  List<Message> get messages => _messages;

  @override
  AiChanProfile? get profile => _profile;

  @override
  Future<void> initialize() async {
    // Implementación básica
  }

  @override
  Future<void> clearMessages() async {
    _messages.clear();
  }

  @override
  Future<void> saveState() async {
    // TODO: Implementar persistencia
  }

  @override
  void dispose() {
    _messages.clear();
  }

  @override
  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
  }) async {
    // TODO: Implementar envío de mensaje
  }

  @override
  dynamic get dataController => null;

  @override
  dynamic get messageController => null;

  @override
  dynamic get callController => null;

  @override
  dynamic get audioController => null;

  @override
  dynamic get googleController => null;
}
