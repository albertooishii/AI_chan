class AIResponse {
  AIResponse({
    required this.text,
    this.seed = '',
    this.prompt = '',
    this.imageFileName = '',
    this.audioFileName = '',
  });

  factory AIResponse.fromJson(final Map<String, dynamic> json) {
    final image = json['image'] ?? {};
    return AIResponse(
      text: json['text'] ?? '',
      seed: image['seed'] ?? '',
      prompt: image['prompt'] ?? '',
      imageFileName: image['file_name'] ?? '',
      audioFileName: json['audio'] is Map
          ? (json['audio']['file_name'] ?? '')
          : (json['audio_file_name'] ?? ''),
    );
  }
  final String text;
  final String seed;
  final String prompt;
  final String imageFileName;
  final String audioFileName;

  Map<String, dynamic> toJson() => {
    'text': text,
    'image': {'seed': seed, 'prompt': prompt, 'file_name': imageFileName},
    'audio': {'file_name': audioFileName},
  };
}
