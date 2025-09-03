import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class ProviderPersistUtils {
  /// Persist an ImportedChat using the provided repository if available,
  /// falling back to SharedPreferences via StorageUtils.
  static Future<void> saveImportedChat(
    ImportedChat imported, {
    IChatRepository? repository,
  }) async {
    if (repository != null) {
      try {
        await repository.saveAll(imported.toJson());
        return;
      } catch (e) {
        Log.w(
          'IChatRepository.saveAll failed, falling back to SharedPreferences: $e',
          tag: 'PERSIST',
        );
      }
    }

    try {
      await StorageUtils.saveImportedChatToPrefs(imported);
    } catch (e) {
      Log.w('StorageUtils.saveImportedChatToPrefs failed: $e', tag: 'PERSIST');
    }
  }
}
