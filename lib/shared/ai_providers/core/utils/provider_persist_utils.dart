import 'package:ai_chan/shared.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';

class ProviderPersistUtils {
  /// Persist a ChatExport using the provided repository if available,
  /// falling back to SharedPreferences via StorageUtils.
  static Future<void> saveChatExport(
    final ChatExport exported, {
    final IChatRepository? repository,
  }) async {
    if (repository != null) {
      try {
        await repository.saveAll(exported.toJson());
        return;
      } on Exception catch (e) {
        Log.w(
          'IChatRepository.saveAll failed, falling back to SharedPreferences: $e',
          tag: 'PERSIST',
        );
      }
    }

    try {
      await StorageUtils.saveChatExportToPrefs(exported);
    } on Exception catch (e) {
      Log.w('StorageUtils.saveChatExportToPrefs failed: $e', tag: 'PERSIST');
    }
  }
}
