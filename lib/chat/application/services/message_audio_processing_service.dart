/// Service responsible for processing audio tags and TTS requests
class MessageAudioProcessingService {
  /// Extract and process [audio]...[/audio] tags from AI response
  AudioProcessingResult processAudioTags(String text) {
    const openTag = '[audio]';
    const closeTag = '[/audio]';

    final lowerText = text.toLowerCase();
    final hasOpen = lowerText.contains(openTag);
    final hasClose = lowerText.contains(closeTag);

    if (!hasOpen || !hasClose) {
      return AudioProcessingResult(ttsRequested: false, cleanedText: text);
    }

    final start = lowerText.indexOf(openTag) + openTag.length;
    final end = lowerText.indexOf(closeTag, start);

    if (end <= start) {
      return AudioProcessingResult(ttsRequested: false, cleanedText: text);
    }

    final inner = text.substring(start, end).trim();
    if (inner.isEmpty) {
      return AudioProcessingResult(ttsRequested: false, cleanedText: text);
    }

    return AudioProcessingResult(
      ttsRequested: true,
      cleanedText: inner, // Replace full tagged text with inner content
    );
  }
}

/// Result of audio processing
class AudioProcessingResult {
  final bool ttsRequested;
  final String cleanedText;

  AudioProcessingResult({
    required this.ttsRequested,
    required this.cleanedText,
  });
}
