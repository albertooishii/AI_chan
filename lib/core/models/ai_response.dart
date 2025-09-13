class AIResponse {
  AIResponse({
    required this.text,
    this.base64 = '',
    this.seed = '',
    this.prompt = '',
    this.imageFileName = '',
  });

  factory AIResponse.fromJson(final Map<String, dynamic> json) {
    final image = json['image'] ?? {};
    return AIResponse(
      text: json['text'] ?? '',
      base64: image['base64'] ?? '',
      seed: image['seed'] ?? '',
      prompt: image['prompt'] ?? '',
      imageFileName: image['file_name'] ?? '',
    );
  }
  final String text;
  final String base64;
  final String seed;
  final String prompt;
  final String imageFileName;

  Map<String, dynamic> toJson() => {
    'text': text,
    'image': {
      'base64': base64,
      'seed': seed,
      'prompt': prompt,
      'file_name': imageFileName,
    },
  };
}
