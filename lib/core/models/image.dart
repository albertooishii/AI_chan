// Copia de lib/models/image.dart para core/shared models
class AiImage {
  final String? base64;
  final String? seed;
  final String? url;
  final String? prompt;

  /// Unix timestamp in milliseconds when this image/avatar was created.
  final int? createdAtMs;

  AiImage({this.base64, this.seed, this.url, this.prompt, this.createdAtMs});

  factory AiImage.fromJson(Map<String, dynamic> json) {
    return AiImage(
      base64: json['base64'] as String?,
      seed: json['seed'] as String?,
      url: json['url'] as String?,
      prompt: json['prompt'] as String?,
      createdAtMs: json['createdAtMs'] is int
          ? json['createdAtMs'] as int
          : (json['createdAtMs'] is String
                ? int.tryParse(json['createdAtMs'])
                : null),
    );
  }

  Map<String, dynamic> toJson() => {
    if (base64 != null) 'base64': base64,
    if (seed != null) 'seed': seed,
    if (url != null) 'url': url,
    if (prompt != null) 'prompt': prompt,
    if (createdAtMs != null) 'createdAtMs': createdAtMs,
  };

  AiImage copyWith({
    String? base64,
    String? seed,
    String? url,
    String? prompt,
    int? createdAtMs,
  }) {
    return AiImage(
      base64: base64 ?? this.base64,
      seed: seed ?? this.seed,
      url: url ?? this.url,
      prompt: prompt ?? this.prompt,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }
}

// It was removed to avoid ambiguity with Flutter's Image widget. Use `AiImage` explicitly.
