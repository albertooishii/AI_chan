import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/domain/interfaces/i_profile_persistence_service.dart';

/// Helpers to update and persist profile data across bounded contexts.
/// Uses shared domain interfaces to maintain clean architecture.
///
/// ✅ DDD COMPLIANT: Shared utilities accessible across bounded contexts

Future<void> setOnboardingDataAndPersist(
  final AiChanProfile updated, {
  final IProfilePersistenceService? persistenceService,
}) async {
  final persistService =
      persistenceService ?? SharedProfilePersistenceServiceAdapter();

  try {
    await persistService.setOnboardingDataAndPersist(updated);
    Log.d(
      'profile_persist_utils: persisted onboarding data for aiName=${updated.aiName}',
    );
  } on Exception catch (e, st) {
    Log.e(
      'profile_persist_utils: failed to persist onboarding data for aiName=${updated.aiName} error=$e',
      tag: 'PERSIST',
      error: e,
    );
    Log.e(st.toString(), tag: 'PERSIST');
    rethrow;
  }
}

/// Convenience helper to update only the events list and persist.
///
/// ✅ DDD COMPLIANT: Shared utilities accessible across bounded contexts
Future<void> setEventsAndPersist(
  final List<ChatEvent> events, {
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
