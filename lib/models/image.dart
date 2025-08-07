class Image {
  final String? base64;
  final String? seed;
  final String? url;
  final String? prompt;

  Image({this.base64, this.seed, this.url, this.prompt});

  factory Image.fromJson(Map<String, dynamic> json) {
    return Image(
      base64: json['base64'] as String?,
      seed: json['seed'] as String?,
      url: json['url'] as String?,
      prompt: json['prompt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (base64 != null) 'base64': base64,
    if (seed != null) 'seed': seed,
    if (url != null) 'url': url,
    if (prompt != null) 'prompt': prompt,
  };

  Image copyWith({String? base64, String? seed, String? url, String? prompt}) {
    return Image(
      base64: base64 ?? this.base64,
      seed: seed ?? this.seed,
      url: url ?? this.url,
      prompt: prompt ?? this.prompt,
    );
  }
}
