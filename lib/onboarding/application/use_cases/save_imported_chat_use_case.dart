import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/shared/utils/provider_persist_utils.dart';

/// Application-level wrapper to persist an imported chat.
/// Keeps persistence details out of UI layers (providers/controllers).
class SaveImportedChatUseCase {
  SaveImportedChatUseCase();

  Future<void> saveImportedChat(
    ImportedChat imported, {
    IChatRepository? repository,
  }) async {
    await ProviderPersistUtils.saveImportedChat(
      imported,
      repository: repository,
    );
  }
}
