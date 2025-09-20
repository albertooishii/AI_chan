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
