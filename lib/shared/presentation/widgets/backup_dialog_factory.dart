import 'package:ai_chan/shared.dart'; // Using shared exports for infrastructure
import 'package:ai_chan/chat/presentation/controllers/chat_controller.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/shared/presentation/widgets/google_drive_backup_dialog.dart';

/// 🏭 **Backup Dialog Factory** - Type-safe factory for creating backup dialogs
///
/// This factory provides type-safe methods for creating GoogleDriveBackupDialog
/// with proper typing to prevent runtime errors from incorrect property access.
///
/// **Benefits:**
/// ✅ Type safety - prevents `onboardingData` vs `profile` errors
/// ✅ Consistent interface - same callback structure across app
/// ✅ Error prevention - compile-time type checking
/// ✅ Maintainable - centralized backup dialog creation
class BackupDialogFactory {
  /// Creates a GoogleDriveBackupDialog from a ChatController
  ///
  /// This method ensures type safety by explicitly typing the provider
  /// parameter and using the correct property access patterns.
  static GoogleDriveBackupDialog fromChatController(
    final ChatController chatController,
  ) {
    return GoogleDriveBackupDialog(
      requestBackupJson: () async {
        return await BackupUtils.exportChatPartsToJson(
          profile: chatController.profile!,
          messages: chatController.messages,
          events: chatController.events,
          timeline: chatController.timeline,
        );
      },
      onImportedJson: (final jsonStr) async {
        final imported = await ChatJsonUtils.importAllFromJson(jsonStr);
        if (imported != null) {
          await chatController.applyChatExport(imported.toJson());
        }
      },
      onAccountInfoUpdated:
          ({
            final String? email,
            final String? avatarUrl,
            final String? name,
            final bool linked = false,
            final bool triggerAutoBackup = false,
          }) async {
            await chatController.googleController.updateGoogleAccountInfo(
              email: email,
              avatarUrl: avatarUrl,
              name: name,
              linked: linked,
              triggerAutoBackup: triggerAutoBackup,
            );
          },
      onClearAccountInfo: () =>
          chatController.googleController.clearGoogleAccountInfo(),
    );
  }

  /// Creates a GoogleDriveBackupDialog from a ChatApplicationService
  ///
  /// This method ensures type safety for onboarding contexts where
  /// ChatApplicationService is used directly.
  static GoogleDriveBackupDialog fromChatApplicationService(
    final ChatApplicationService chatService,
  ) {
    return GoogleDriveBackupDialog(
      requestBackupJson: () async {
        return await BackupUtils.exportChatPartsToJson(
          profile: chatService.profile!,
          messages: chatService.messages,
          events: chatService.events,
          timeline: chatService.timeline,
        );
      },
      onImportedJson: (final jsonStr) async {
        final imported = await ChatJsonUtils.importAllFromJson(jsonStr);
        if (imported != null) {
          await chatService.applyChatExport(imported.toJson());
        }
      },
      onAccountInfoUpdated:
          ({
            final String? email,
            final String? avatarUrl,
            final String? name,
            final bool linked = false,
            final bool triggerAutoBackup = false,
          }) async {
            await chatService.updateGoogleAccountInfo(
              email: email,
              avatarUrl: avatarUrl,
              name: name,
              linked: linked,
              triggerAutoBackup: triggerAutoBackup,
            );
          },
      onClearAccountInfo: () => chatService.clearGoogleAccountInfo(),
    );
  }
}
