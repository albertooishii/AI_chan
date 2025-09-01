// Audio model for AI_chan - follows same pattern as AiImage
class AiAudio {
  /// Path or URL to the audio file
  final String? url;

  /// Transcript/text content of the audio
  final String? transcript;

  /// Duration of the audio file in milliseconds
  final int? durationMs;

  /// Unix timestamp in milliseconds when this audio was created
  final int? createdAtMs;

  /// Whether this audio was auto-generated via TTS
  final bool? isAutoTts;

  AiAudio({
    this.url,
    this.transcript,
    this.durationMs,
    this.createdAtMs,
    this.isAutoTts,
  });

  factory AiAudio.fromJson(Map<String, dynamic> json) {
    return AiAudio(
      url: json['url'] as String?,
      transcript: json['transcript'] as String?,
      durationMs: json['durationMs'] is int
          ? json['durationMs'] as int
          : (json['durationMs'] is String
                ? int.tryParse(json['durationMs'])
                : null),
      createdAtMs: json['createdAtMs'] is int
          ? json['createdAtMs'] as int
          : (json['createdAtMs'] is String
                ? int.tryParse(json['createdAtMs'])
                : null),
      isAutoTts: json['isAutoTts'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (url != null) 'url': url,
    if (transcript != null) 'transcript': transcript,
    if (durationMs != null) 'durationMs': durationMs,
    if (createdAtMs != null) 'createdAtMs': createdAtMs,
    if (isAutoTts != null) 'isAutoTts': isAutoTts,
  };

  AiAudio copyWith({
    String? url,
    String? transcript,
    int? durationMs,
    int? createdAtMs,
    bool? isAutoTts,
  }) {
    return AiAudio(
      url: url ?? this.url,
      transcript: transcript ?? this.transcript,
      durationMs: durationMs ?? this.durationMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      isAutoTts: isAutoTts ?? this.isAutoTts,
    );
  }

  /// Get duration as Duration object
  Duration? get duration =>
      durationMs != null ? Duration(milliseconds: durationMs!) : null;
}
