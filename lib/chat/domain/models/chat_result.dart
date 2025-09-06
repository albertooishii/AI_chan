/// Result of an AI chat response containing text, image data, and metadata
class ChatResult {
  ChatResult({
    required this.text,
    required this.isImage,
    required this.imagePath,
    required this.prompt,
    required this.seed,
    required this.finalModelUsed,
  });
  final String text;
  final bool isImage;
  final String? imagePath;
  final String? prompt;
  final String? seed;
  final String finalModelUsed;

  @override
  String toString() =>
      'ChatResult(text: $text, isImage: $isImage, model: $finalModelUsed)';
}
