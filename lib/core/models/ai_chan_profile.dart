import 'package:ai_chan/core/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiChanProfile {
  final List<EventEntry>? events;
  // Todos los campos al mismo nivel (estructura plana)
  final String userName;
  final String aiName;
  final DateTime? userBirthday;
  final DateTime? aiBirthday;
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
    required this.userBirthday,
    required this.aiBirthday,
    required this.biography,
    required this.appearance,
    required this.timeline,
    this.userCountryCode,
    this.aiCountryCode,
    this.avatars,
  });

  /// Backwards-compat getter: última avatar si existe.
  AiImage? get avatar => (avatars != null && avatars!.isNotEmpty) ? avatars!.last : null;

  /// Nuevo getter explícito para obtener el PRIMER avatar (avatars[0])
  /// Use esto cuando se desea la versión histórica/primera del avatar.
  AiImage? get firstAvatar => (avatars != null && avatars!.isNotEmpty) ? avatars!.first : null;

  factory AiChanProfile.fromJson(Map<String, dynamic> json) {
    final events = (json['events'] as List<dynamic>? ?? [])
        .map((e) => EventEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    DateTime? birth;
    if (json['userBirthday'] is String && (json['userBirthday'] as String).isNotEmpty) {
      birth = DateTime.tryParse(json['userBirthday']);
    }
    DateTime? aiBirth;
    if (json['aiBirthday'] is String && (json['aiBirthday'] as String).isNotEmpty) {
      aiBirth = DateTime.tryParse(json['aiBirthday']);
    }
    return AiChanProfile(
      userName: json['userName'] ?? '',
      aiName: json['aiName'] ?? '',
      userBirthday: birth,
      aiBirthday: aiBirth,
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
      // Compatibilidad: soportar tanto 'avatars' (lista) como el campo legacy 'avatar'.
      avatars: (() {
        try {
          if (json['avatars'] is List) {
            final list = (json['avatars'] as List).cast<Map<String, dynamic>>();
            return list.map((m) => AiImage.fromJson(m)).toList();
          }
          if (json['avatar'] != null) {
            return [AiImage.fromJson(json['avatar'] as Map<String, dynamic>)];
          }
        } catch (_) {}
        return null;
      })(),
    );
  }

  /// Versión segura: devuelve null y borra datos corruptos si el perfil no es válido (estructura plana)
  static Future<AiChanProfile?> tryFromJson(Map<String, dynamic> json) async {
    // Estructura esperada: todos los campos al mismo nivel
    final expectedKeys = ['userName', 'aiName', 'biography', 'appearance', 'timeline'];
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('onboarding_data');
        await prefs.remove('chat_history');
      } catch (_) {}
      return null;
    }
    return AiChanProfile.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'aiName': aiName,
    'userBirthday': userBirthday != null
        ? "${userBirthday!.year.toString().padLeft(4, '0')}-${userBirthday!.month.toString().padLeft(2, '0')}-${userBirthday!.day.toString().padLeft(2, '0')}"
        : null,
    'aiBirthday': aiBirthday != null
        ? "${aiBirthday!.year.toString().padLeft(4, '0')}-${aiBirthday!.month.toString().padLeft(2, '0')}-${aiBirthday!.day.toString().padLeft(2, '0')}"
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
    DateTime? userBirthday,
    DateTime? aiBirthday,
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
      userBirthday: userBirthday ?? this.userBirthday,
      aiBirthday: aiBirthday ?? this.aiBirthday,
      biography: biography ?? this.biography,
      appearance: appearance ?? this.appearance,
      timeline: timeline ?? this.timeline,
      userCountryCode: userCountryCode ?? this.userCountryCode,
      aiCountryCode: aiCountryCode ?? this.aiCountryCode,
      avatars: avatars ?? this.avatars,
    );
  }
}
