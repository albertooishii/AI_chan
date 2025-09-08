import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/provider_persist_utils.dart';

/// Application-level wrapper to persist an exported chat.
/// Keeps persistence details out of UI layers (providers/controllers).
class SaveChatExportUseCase {
  SaveChatExportUseCase();

  Future<void> saveChatExport(
    final ChatExport exported, {
    // TODO: Usar interfaz de onboarding en lugar de IChatRepository
    final Object? repository,
  }) async {
    // TODO: Implementar usando la interfaz de onboarding
    await ProviderPersistUtils.saveChatExport(exported);
  }
}
