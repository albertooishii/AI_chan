import 'dart:convert';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/domain/interfaces/i_profile_persistence_service.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

/// Infrastructure adapter that implements shared profile persistence interface
/// by delegating to PrefsUtils for direct SharedPreferences access.
class SharedProfilePersistenceServiceAdapter
    implements IProfilePersistenceService {
  @override
  Future<void> setOnboardingDataAndPersist(final AiChanProfile profile) async {
    final profileJson = jsonEncode(profile.toJson());
    await PrefsUtils.setOnboardingData(profileJson);
  }

  @override
  Future<void> setEventsAndPersist(final List<EventEntry> events) async {
    final eventsJson = jsonEncode(events.map((final e) => e.toJson()).toList());
    await PrefsUtils.setEvents(eventsJson);
  }
}
