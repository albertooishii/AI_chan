/// 🎯 DDD: Value Object para configuración de voz
/// Inmutable, con validación de negocio integrada
class VoiceSettings {
  /// Factory con validación de negocio
  factory VoiceSettings.create({
    required final String voiceId,
    required final String language,
    final double speed = 1.0,
    final double pitch = 1.0,
    final double volume = 1.0,
    final String? emotionalTone,
  }) {
    if (voiceId.trim().isEmpty) {
      throw ArgumentError('VoiceId no puede estar vacío');
    }
    if (language.trim().isEmpty) {
      throw ArgumentError('Language no puede estar vacío');
    }
    if (speed < 0.1 || speed > 4.0) {
      throw ArgumentError('Speed debe estar entre 0.1 y 4.0');
    }
    if (pitch < 0.1 || pitch > 2.0) {
      throw ArgumentError('Pitch debe estar entre 0.1 y 2.0');
    }
    if (volume < 0.0 || volume > 1.0) {
      throw ArgumentError('Volume debe estar entre 0.0 y 1.0');
    }

    return VoiceSettings(
      voiceId: voiceId.trim(),
      language: language.trim(),
      speed: speed,
      pitch: pitch,
      volume: volume,
      emotionalTone: emotionalTone?.trim(),
    );
  }

  /// Factory para configuración por defecto
  factory VoiceSettings.defaultSettings({final String language = 'es-ES'}) {
    return VoiceSettings.create(voiceId: 'alloy', language: language);
  }

  /// Deserialización
  factory VoiceSettings.fromJson(final Map<String, dynamic> json) {
    return VoiceSettings.create(
      voiceId: json['voiceId'] as String,
      language: json['language'] as String,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      emotionalTone: json['emotionalTone'] as String?,
    );
  }
  const VoiceSettings({
    required this.voiceId,
    required this.language,
    this.speed = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.emotionalTone,
  });

  final String voiceId;
  final String language;
  final double speed;
  final double pitch;
  final double volume;
  final String? emotionalTone;

  /// Copia inmutable con cambios
  VoiceSettings copyWith({
    final String? voiceId,
    final String? language,
    final double? speed,
    final double? pitch,
    final double? volume,
    final String? emotionalTone,
  }) {
    return VoiceSettings.create(
      voiceId: voiceId ?? this.voiceId,
      language: language ?? this.language,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      emotionalTone: emotionalTone ?? this.emotionalTone,
    );
  }

  /// Serialización
  Map<String, dynamic> toJson() {
    return {
      'voiceId': voiceId,
      'language': language,
      'speed': speed,
      'pitch': pitch,
      'volume': volume,
      'emotionalTone': emotionalTone,
    };
  }

  @override
  String toString() => 'VoiceSettings($voiceId, $language, speed: $speed)';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is VoiceSettings &&
          runtimeType == other.runtimeType &&
          voiceId == other.voiceId &&
          language == other.language &&
          speed == other.speed &&
          pitch == other.pitch &&
          volume == other.volume &&
          emotionalTone == other.emotionalTone;

  @override
  int get hashCode =>
      Object.hash(voiceId, language, speed, pitch, volume, emotionalTone);
}
