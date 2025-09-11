/// Voice information model for AI providers
///
/// This model is used by all AI providers to represent voice information
/// including name, gender, and provider-specific metadata.
class VoiceInfo {
  // Optional description

  const VoiceInfo({
    required this.name,
    required this.gender,
    this.languageCodes,
    this.sampleRate,
    this.description,
  });

  /// Create from map for deserialization
  factory VoiceInfo.fromMap(final Map<String, dynamic> map) {
    return VoiceInfo(
      name: map['name'] ?? '',
      gender: map['gender'] ?? 'Desconocido',
      languageCodes: (map['languageCodes'] as List?)?.cast<String>(),
      sampleRate: map['sampleRate'] as int?,
      description: map['description'] as String?,
    );
  }
  final String name;
  final String gender; // 'Femenina', 'Masculina', 'Neutral'
  final List<String>? languageCodes; // For Google TTS
  final int? sampleRate; // For Google TTS
  final String? description;

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'gender': gender,
      'languageCodes': languageCodes,
      'sampleRate': sampleRate,
      'description': description,
    };
  }

  @override
  String toString() => 'VoiceInfo(name: $name, gender: $gender)';

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is VoiceInfo && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}
