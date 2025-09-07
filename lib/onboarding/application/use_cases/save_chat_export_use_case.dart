import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/shared/utils/provider_persist_utils.dart';

/// Application-level wrapper to persist an exported chat.
/// Keeps persistence details out of UI layers (providers/controllers).
class SaveChatExportUseCase {
  SaveChatExportUseCase();

  Future<void> saveChatExport(final ChatExport exported, {final IChatRepository? repository}) async {
    await ProviderPersistUtils.saveChatExport(exported, repository: repository);
  }
}
