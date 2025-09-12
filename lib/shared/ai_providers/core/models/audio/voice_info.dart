/// 🎯 DDD: Info de voz disponible
class VoiceInfo {
  const VoiceInfo({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
    this.description,
  });

  final String id;
  final String name;
  final String language;
  final VoiceGender gender;
  final String? description;

  @override
  String toString() => 'VoiceInfo($id: $name, $language, $gender)';
}

/// 🎯 DDD: Género de voz
enum VoiceGender { male, female, neutral, unknown }

extension VoiceGenderExtension on VoiceGender {
  String get displayName {
    switch (this) {
      case VoiceGender.male:
        return 'Masculina';
      case VoiceGender.female:
        return 'Femenina';
      case VoiceGender.neutral:
        return 'Neutral';
      case VoiceGender.unknown:
        return 'Desconocido';
    }
  }
}
