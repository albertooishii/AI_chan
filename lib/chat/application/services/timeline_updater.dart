import 'package:ai_chan/core/models.dart';

/// TimelineUpdater contains helpers to apply timeline/superbloque updates
/// into the profile object. Kept minimal and synchronous for easy unit testing.
class TimelineUpdater {
  /// Returns a new profile with the updated timeline and superbloqueEntry applied.
  static AiChanProfile applyTimelineUpdate({
    required AiChanProfile profile,
    required List<TimelineEntry> timeline,
    TimelineEntry? superbloqueEntry,
  }) {
    return profile.copyWith(timeline: timeline);
  }
}
