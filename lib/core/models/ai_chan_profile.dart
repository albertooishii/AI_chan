import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

class AiChanProfile {
  final List<EventEntry>? events;
  // Todos los campos al mismo nivel (estructura plana)
  final String userName;
  final String aiName;
  final DateTime? userBirthdate;
  final DateTime? aiBirthdate;
  final Map<String, dynamic> biography;
  final Map<String, dynamic> appearance;
  final List<TimelineEntry> timeline;

  /// Países (ISO-3166 alfa-2) del usuario y de la IA para adaptar idioma/acento
  final String? userCountryCode; // p.ej., ES, US, MX
  final String? aiCountryCode; // p.ej., JP, ES, US

  /// Datos de avatar: ahora soportamos múltiples versiones/variantes.
  /// `avatars` contiene el histórico (orden cronológico). Para compatibilidad
  /// con código existente hay un getter `avatar` que devuelve la última.
  final List<AiImage>? avatars;

  AiChanProfile({
    this.events,
    required this.userName,
    required this.aiName,
    required this.userBirthdate,
    required this.aiBirthdate,
    required this.biography,
    required this.appearance,
    required this.timeline,
    this.userCountryCode,
    this.aiCountryCode,
    this.avatars,
  });

  /// Backwards-compat getter: última avatar si existe.
  AiImage? get avatar =>
      (avatars != null && avatars!.isNotEmpty) ? avatars!.last : null;

  /// Nuevo getter explícito para obtener el PRIMER avatar (avatars[0])
  /// Use esto cuando se desea la versión histórica/primera del avatar.
  AiImage? get firstAvatar =>
      (avatars != null && avatars!.isNotEmpty) ? avatars!.first : null;

  factory AiChanProfile.fromJson(Map<String, dynamic> json) {
    final events = (json['events'] as List<dynamic>? ?? [])
        .map((e) => EventEntry.fromJson(e as Map<String, dynamic>))
        .toList();
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
      events: events.isNotEmpty ? events : null,
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      // Avatars: expect a list under 'avatars' only (legacy single 'avatar' removed)
      avatars: (() {
        try {
          if (json['avatars'] is List) {
            final list = (json['avatars'] as List).cast<Map<String, dynamic>>();
            return list.map((m) => AiImage.fromJson(m)).toList();
          }
        } catch (_) {}
        return null;
      })(),
    );
  }

  /// Versión segura: devuelve null y borra datos corruptos si el perfil no es válido (estructura plana)
  static Future<AiChanProfile?> tryFromJson(Map<String, dynamic> json) async {
    // Estructura esperada: todos los campos al mismo nivel
    final expectedKeys = [
      'userName',
      'aiName',
      'biography',
      'appearance',
      'timeline',
    ];
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
          json['appearance'] is Map<String, dynamic> &&
          json['timeline'] is List;
    }
    if (!valid) {
      try {
        await PrefsUtils.removeOnboardingData();
        await PrefsUtils.removeChatHistory();
      } catch (_) {}
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
    if (avatars != null) 'avatars': avatars!.map((a) => a.toJson()).toList(),
    if (events != null) 'events': events!.map((e) => e.toJson()).toList(),
    // timeline SIEMPRE debe ir al final para mantener el orden y evitar problemas de import/export
    'timeline': timeline.map((e) => e.toJson()).toList(),
  }..removeWhere((k, v) => v == null);

  AiChanProfile copyWith({
    List<EventEntry>? events,
    String? userName,
    String? aiName,
    DateTime? userBirthdate,
    DateTime? aiBirthdate,
    Map<String, dynamic>? biography,
    Map<String, dynamic>? appearance,
    List<TimelineEntry>? timeline,
    String? userCountryCode,
    String? aiCountryCode,
    List<AiImage>? avatars,
  }) {
    return AiChanProfile(
      events: events ?? this.events,
      userName: userName ?? this.userName,
      aiName: aiName ?? this.aiName,
      userBirthdate: userBirthdate ?? this.userBirthdate,
      aiBirthdate: aiBirthdate ?? this.aiBirthdate,
      biography: biography ?? this.biography,
      appearance: appearance ?? this.appearance,
      timeline: timeline ?? this.timeline,
      userCountryCode: userCountryCode ?? this.userCountryCode,
      aiCountryCode: aiCountryCode ?? this.aiCountryCode,
      avatars: avatars ?? this.avatars,
    );
  }
}
