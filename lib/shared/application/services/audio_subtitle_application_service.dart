/// Word timeline item for audio subtitles
class WordTimelineItem {
  const WordTimelineItem({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.appendSpace = true,
  });

  final String text;
  final int startMs;
  final int endMs;
  final bool appendSpace;
}

/// Application Service for managing audio subtitle synchronization and progressive text reveal
class AudioSubtitleApplicationService {
  /// Generates progressive text based on audio position and timeline
  String generateProgressiveText({
    required final Duration audioPosition,
    required final List<WordTimelineItem> timeline,
    required final Duration totalDuration,
  }) {
    if (timeline.isEmpty || totalDuration.inMilliseconds <= 0) {
      return '';
    }

    final positionMs = audioPosition.inMilliseconds;
    final buffer = StringBuffer();

    for (final word in timeline) {
      if (word.startMs <= positionMs) {
        buffer.write(word.text);
        if (word.appendSpace && !word.text.endsWith(' ')) {
          buffer.write(' ');
        }
      } else {
        break;
      }
    }

    return buffer.toString().trimRight();
  }

  /// Validates timeline data integrity
  bool validateTimeline(final List<WordTimelineItem> timeline) {
    if (timeline.isEmpty) return true;

    for (int i = 0; i < timeline.length; i++) {
      final word = timeline[i];

      // Basic validation
      if (word.startMs < 0 || word.endMs < 0 || word.startMs > word.endMs) {
        return false;
      }

      // Sequential validation
      if (i > 0 && word.startMs < timeline[i - 1].startMs) {
        return false;
      }
    }

    return true;
  }

  /// Calculates completion percentage based on position
  double calculateCompletionPercentage({
    required final Duration audioPosition,
    required final Duration totalDuration,
  }) {
    if (totalDuration.inMilliseconds <= 0) return 0.0;

    final ratio = audioPosition.inMilliseconds / totalDuration.inMilliseconds;
    return (ratio * 100).clamp(0.0, 100.0);
  }

  /// Finds the current word being spoken at given position
  WordTimelineItem? findCurrentWord({
    required final Duration audioPosition,
    required final List<WordTimelineItem> timeline,
  }) {
    final positionMs = audioPosition.inMilliseconds;

    for (final word in timeline) {
      if (positionMs >= word.startMs && positionMs <= word.endMs) {
        return word;
      }
    }

    return null;
  }
}
