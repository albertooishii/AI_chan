import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/domain/interfaces/i_profile_persistence_service.dart';
import 'package:ai_chan/shared/domain/interfaces/i_shared_logger.dart';

/// Helpers to update and persist profile data across bounded contexts.
/// Uses shared domain interfaces to maintain clean architecture.
///
/// ✅ DDD COMPLIANT: Shared utilities accessible across bounded contexts

Future<void> setOnboardingDataAndPersist(
  final AiChanProfile updated, {
  final ISharedLogger? logger,
  final IProfilePersistenceService? persistenceService,
}) async {
  final sharedLogger = logger ?? SharedLoggerAdapter();
  final persistService =
      persistenceService ?? SharedProfilePersistenceServiceAdapter();

  try {
    await persistService.setOnboardingDataAndPersist(updated);
    sharedLogger.debug(
      'profile_persist_utils: persisted onboarding data for aiName=${updated.aiName}',
    );
  } on Exception catch (e, st) {
    sharedLogger.error(
      'profile_persist_utils: failed to persist onboarding data for aiName=${updated.aiName} error=$e',
      tag: 'PERSIST',
      error: e,
    );
    sharedLogger.error(st.toString(), tag: 'PERSIST');
    rethrow;
  }
}

/// Convenience helper to update only the events list and persist.
///
/// ✅ DDD COMPLIANT: Shared utilities accessible across bounded contexts
Future<void> setEventsAndPersist(
  final List<ChatEvent> events, {
  final ISharedLogger? logger,
  final IProfilePersistenceService? persistenceService,
}) async {
  final persistService =
      persistenceService ?? SharedProfilePersistenceServiceAdapter();

  try {
    await persistService.setEventsAndPersist(events);
  } on Exception catch (_) {
    // Handle errors silently as in original implementation
  }
}
