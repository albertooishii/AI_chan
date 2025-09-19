import 'package:ai_chan/chat/domain/interfaces/i_chat_avatar_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart';
import 'package:ai_chan/shared.dart';

/// Implementación del servicio de avatar que actúa como adapter
/// para el controlador de chat
class ChatAvatarServiceAdapter implements IChatAvatarService {
  const ChatAvatarServiceAdapter(this._chatController);
  final IChatController _chatController;

  @override
  AiChanProfile? get currentProfile => _chatController.profile;

  @override
  Future<void> updateProfileWithAvatar(final AiImage avatar) async {
    // TODO: Implementar cuando IChatController tenga métodos de profile
    // Por ahora es un stub para cumplir con el contrato
  }

  @override
  List<AiImage> get profileAvatars => currentProfile?.avatars ?? [];

  @override
  Future<void> addAvatar(final AiImage avatar) async {
    await updateProfileWithAvatar(avatar);
  }

  @override
  Future<void> persistProfile() async {
    await _chatController.saveState();
  }

  @override
  void notifyProfileChanged() {
    // TODO: Implementar notificación cuando IChatController lo soporte
  }
}
