// Copia de lib/models/image.dart para core/shared models
class AiImage {
  AiImage({this.seed, this.url, this.prompt, this.createdAtMs});

  factory AiImage.fromJson(final Map<String, dynamic> json) {
    return AiImage(
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
  final String? seed;
  final String? url;
  final String? prompt;

  /// Unix timestamp in milliseconds when this image/avatar was created.
  final int? createdAtMs;

  Map<String, dynamic> toJson() => {
    if (seed != null) 'seed': seed,
    if (url != null) 'url': url,
    if (prompt != null) 'prompt': prompt,
    if (createdAtMs != null) 'createdAtMs': createdAtMs,
  };

  AiImage copyWith({
    final String? seed,
    final String? url,
    final String? prompt,
    final int? createdAtMs,
  }) {
    return AiImage(
      seed: seed ?? this.seed,
      url: url ?? this.url,
      prompt: prompt ?? this.prompt,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }
}

// It was removed to avoid ambiguity with Flutter's Image widget. Use `AiImage` explicitly.
