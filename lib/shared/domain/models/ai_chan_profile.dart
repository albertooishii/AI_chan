import 'package:ai_chan/shared.dart';

/// Perfil limpio del usuario/AI sin información de timeline, eventos o mensajes.
/// Contiene únicamente la información básica del perfil y biografía.
class AiChanProfile {
  AiChanProfile({
    required this.userName,
    required this.aiName,
    required this.userBirthdate,
    required this.aiBirthdate,
    required this.biography,
    required this.appearance,
    this.userCountryCode,
    this.aiCountryCode,
    this.avatars,
  });

  factory AiChanProfile.fromJson(final Map<String, dynamic> json) {
    DateTime? birth;
    if (json['userBirthdate'] is String &&
        (json['userBirthdate'] as String).isNotEmpty) {
      birth = DateTime.tryParse(json['userBirthdate']);
    }
    DateTime? aiBirth;
    if (json['aiBirthdate'] is String &&
        (json['aiBirthdate'] as String).isNotEmpty) {
      aiBirth = DateTime.tryParse(json['aiBirthdate']);
    }
    return AiChanProfile(
      userName: json['userName'] ?? '',
      aiName: json['aiName'] ?? '',
      userBirthdate: birth,
      aiBirthdate: aiBirth,
      biography: json['biography'] is Map<String, dynamic>
          ? json['biography'] as Map<String, dynamic>
          : <String, dynamic>{},
      appearance: json['appearance'] is Map<String, dynamic>
          ? json['appearance'] as Map<String, dynamic>
          : <String, dynamic>{},
      userCountryCode: json['userCountryCode'] as String?,
      aiCountryCode: json['aiCountryCode'] as String?,
      // Avatars: expect a list under 'avatars' only (legacy single 'avatar' removed)
      avatars: (() {
        try {
          if (json['avatars'] is List) {
            final list = (json['avatars'] as List).cast<Map<String, dynamic>>();
            return list.map((final m) => AiImage.fromJson(m)).toList();
          }
        } on Exception catch (_) {}
        return null;
      })(),
    );
  }
  // Información básica del perfil en orden específico
  final String userName;
  final String aiName;
  final DateTime? userBirthdate;
  final DateTime? aiBirthdate;
  final Map<String, dynamic> biography;
  final Map<String, dynamic> appearance;

  /// Países (ISO-3166 alfa-2) del usuario y de la IA para adaptar idioma/acento
  final String? userCountryCode; // p.ej., ES, US, MX
  final String? aiCountryCode; // p.ej., JP, ES, US

  /// Datos de avatar: ahora soportamos múltiples versiones/variantes.
  /// `avatars` contiene el histórico (orden cronológico). Para compatibilidad
  /// con código existente hay un getter `avatar` que devuelve la última.
  final List<AiImage>? avatars;

  /// Backwards-compat getter: última avatar si existe.
  AiImage? get avatar =>
      (avatars != null && avatars!.isNotEmpty) ? avatars!.last : null;

  /// Nuevo getter explícito para obtener el PRIMER avatar (avatars[0])
  /// Use esto cuando se desea la versión histórica/primera del avatar.
  AiImage? get firstAvatar =>
      (avatars != null && avatars!.isNotEmpty) ? avatars!.first : null;

  /// Versión segura: devuelve null si el perfil no es válido
  /// Esta es una operación pura del dominio sin efectos secundarios
  static AiChanProfile? tryFromJson(final Map<String, dynamic> json) {
    // Estructura esperada: campos básicos del perfil
    final expectedKeys = ['userName', 'aiName', 'biography', 'appearance'];
    bool valid = true;
    for (final key in expectedKeys) {
      if (!json.containsKey(key)) {
        valid = false;
        break;
      }
    }
    // Tipos esperados
    if (valid) {
      valid =
          json['userName'] is String &&
          (json['userName'] as String).isNotEmpty &&
          json['aiName'] is String &&
          (json['aiName'] as String).isNotEmpty &&
          json['biography'] is Map<String, dynamic> &&
          json['appearance'] is Map<String, dynamic>;
    }
    if (!valid) {
      // Domain models should not have side effects
      // Data cleanup is an application/infrastructure concern
      return null;
    }
    return AiChanProfile.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'aiName': aiName,
    'userBirthdate': userBirthdate != null
        ? "${userBirthdate!.year.toString().padLeft(4, '0')}-${userBirthdate!.month.toString().padLeft(2, '0')}-${userBirthdate!.day.toString().padLeft(2, '0')}"
        : null,
    'aiBirthdate': aiBirthdate != null
        ? "${aiBirthdate!.year.toString().padLeft(4, '0')}-${aiBirthdate!.month.toString().padLeft(2, '0')}-${aiBirthdate!.day.toString().padLeft(2, '0')}"
        : null,
    'biography': biography,
    'appearance': appearance,
    if (userCountryCode != null) 'userCountryCode': userCountryCode,
    if (aiCountryCode != null) 'aiCountryCode': aiCountryCode,
    if (avatars != null)
      'avatars': avatars!.map((final a) => a.toJson()).toList(),
  }..removeWhere((final k, final v) => v == null);

  AiChanProfile copyWith({
    final String? userName,
    final String? aiName,
    final DateTime? userBirthdate,
    final DateTime? aiBirthdate,
    final Map<String, dynamic>? biography,
    final Map<String, dynamic>? appearance,
    final String? userCountryCode,
    final String? aiCountryCode,
    final List<AiImage>? avatars,
  }) {
    return AiChanProfile(
      userName: userName ?? this.userName,
      aiName: aiName ?? this.aiName,
      userBirthdate: userBirthdate ?? this.userBirthdate,
      aiBirthdate: aiBirthdate ?? this.aiBirthdate,
      biography: biography ?? this.biography,
      appearance: appearance ?? this.appearance,
      userCountryCode: userCountryCode ?? this.userCountryCode,
      aiCountryCode: aiCountryCode ?? this.aiCountryCode,
      avatars: avatars ?? this.avatars,
    );
  }
}
