/// Result of an AI chat response containing text, image data, and metadata
class ChatResult {
  ChatResult({
    required this.text,
    required this.isImage,
    required this.imagePath,
    required this.prompt,
    required this.seed,
  });
  final String text;
  final bool isImage;
  final String? imagePath;
  final String? prompt;
  final String? seed;

  @override
  String toString() => 'ChatResult(text: $text, isImage: $isImage)';
}
