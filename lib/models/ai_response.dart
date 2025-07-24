class AIResponse {
  final String text;
  final String imageBase64;
  final String imageId;
  final String revisedPrompt;

  AIResponse({required this.text, this.imageBase64 = '', this.imageId = '', this.revisedPrompt = ''});

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    return AIResponse(
      text: json['text'] ?? '',
      imageBase64: json['imageBase64'] ?? '',
      imageId: json['imageId'] ?? '',
      revisedPrompt: json['revisedPrompt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'imageBase64': imageBase64,
    'imageId': imageId,
    'revisedPrompt': revisedPrompt,
  };
}
