class AIResponse {
  final String text;
  final String base64;
  final String seed;
  final String prompt;

  AIResponse({
    required this.text,
    this.base64 = '',
    this.seed = '',
    this.prompt = '',
  });

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    final image = json['image'] ?? {};
    return AIResponse(
      text: json['text'] ?? '',
      base64: image['base64'] ?? '',
      seed: image['seed'] ?? '',
      prompt: image['prompt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'image': {'base64': base64, 'seed': seed, 'prompt': prompt},
  };
}
