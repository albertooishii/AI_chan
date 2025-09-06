import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

/// Service responsible for retry logic when AI responses are invalid
class MessageRetryService {
  /// Retry sending message with validation and exponential backoff
  Future<AIResponse> sendWithRetries({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final String model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
    final int maxRetries = 3,
  }) async {
    AIResponse response = await AIService.sendMessage(
      history,
      systemPrompt,
      model: model,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    int retry = 0;
    while ((!hasValidText(response) ||
            !hasValidAllowedTagsStructure(response.text)) &&
        retry < maxRetries) {
      final waitSeconds = _extractWaitSeconds(response.text);
      await Future.delayed(Duration(seconds: waitSeconds));

      response = await AIService.sendMessage(
        history,
        systemPrompt,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
      retry++;
    }

    return response;
  }

  int _extractWaitSeconds(final String text) {
    final regex = RegExp(r'try again in ([\d\.]+)s');
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount > 0) {
      return double.tryParse(match.group(1) ?? '8')?.round() ?? 8;
    }
    return 8;
  }

  bool hasValidText(final AIResponse r) {
    final t = r.text.trim();
    if (t.isEmpty) return r.base64.isNotEmpty; // allow only image
    final lower = t.toLowerCase();
    if (lower.contains('error al conectar con la ia')) return false;
    if (lower.contains('"error"')) return false;
    return true;
  }

  bool hasValidAllowedTagsStructure(final String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    final tagToken = RegExp(r'\[/?([a-zA-Z0-9_]+)\]');
    final matches = tagToken.allMatches(trimmed).toList();
    final allowed = {'audio', 'img_caption', 'call', 'end_call', 'no_reply'};
    final tokens = <String>[];
    for (final m in matches) {
      final name = m.group(1);
      if (name == null) continue;
      tokens.add(name.toLowerCase());
    }
    for (final tk in tokens) {
      if (!allowed.contains(tk)) return false;
    }
    if (trimmed.contains('[call]') || trimmed.contains('[end_call]')) {
      final simpleTagPattern = RegExp(
        r'^\s*(\[(?:call|end_call)\]\s*\[/(?:call|end_call)\])\s*$',
      );
      if (!simpleTagPattern.hasMatch(trimmed)) return false;
      return true;
    }
    final imgCaptionOpen = '[img_caption]';
    final imgCaptionClose = '[/img_caption]';
    if (trimmed.contains(imgCaptionOpen)) {
      final firstIdx = trimmed.indexOf(imgCaptionOpen);
      if (firstIdx != 0) return false;
      final closeIdx = trimmed.indexOf(
        imgCaptionClose,
        firstIdx + imgCaptionOpen.length,
      );
      if (closeIdx < 0) return false;
      final after = trimmed
          .substring(closeIdx + imgCaptionClose.length)
          .trimLeft();
      if (after.contains(imgCaptionOpen)) return false;
    }
    final audioOpen = '[audio]';
    final audioClose = '[/audio]';
    if (trimmed.contains(audioOpen)) {
      final openIdx = trimmed.indexOf(audioOpen);
      final closeIdx = trimmed.indexOf(audioClose, openIdx + audioOpen.length);
      if (closeIdx < 0) return false;
      final inner = trimmed
          .substring(openIdx + audioOpen.length, closeIdx)
          .trim();
      if (inner.isEmpty) return false;
      if (inner.startsWith('[')) return false;
      final afterAudio = trimmed.substring(closeIdx + audioClose.length);
      if (afterAudio.contains(audioOpen)) return false;
    }
    bool balanced(final String name) {
      final openCount = RegExp('\\[$name\\]').allMatches(trimmed).length;
      final closeCount = RegExp('\\[/$name\\]').allMatches(trimmed).length;
      return openCount == closeCount;
    }

    for (final name in ['audio', 'img_caption']) {
      if (!balanced(name)) return false;
    }
    return true;
  }
}
