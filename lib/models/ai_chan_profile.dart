import 'timeline_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiChanProfile {
  // Todos los campos al mismo nivel (estructura plana)
  final String userName;
  final String aiName;
  final DateTime? userBirthday;
  final DateTime? aiBirthday;
  final Map<String, dynamic> personality;
  final Map<String, dynamic> biography;
  final Map<String, dynamic> appearance;
  final List<TimelineEntry> timeline;

  AiChanProfile({
    required this.userName,
    required this.aiName,
    required this.userBirthday,
    required this.aiBirthday,
    required this.personality,
    required this.biography,
    required this.appearance,
    required this.timeline,
  });

  factory AiChanProfile.fromJson(Map<String, dynamic> json) {
    DateTime? birth;
    if (json['userBirthday'] is String &&
        (json['userBirthday'] as String).isNotEmpty) {
      birth = DateTime.tryParse(json['userBirthday']);
    }
    DateTime? aiBirth;
    if (json['aiBirthday'] is String &&
        (json['aiBirthday'] as String).isNotEmpty) {
      aiBirth = DateTime.tryParse(json['aiBirthday']);
    }
    return AiChanProfile(
      userName: json['userName'] ?? '',
      aiName: json['aiName'] ?? '',
      userBirthday: birth,
      aiBirthday: aiBirth,
      personality: json['personality'] is Map<String, dynamic>
          ? json['personality'] as Map<String, dynamic>
          : <String, dynamic>{},
      biography: json['biography'] is Map<String, dynamic>
          ? json['biography'] as Map<String, dynamic>
          : <String, dynamic>{},
      appearance: json['appearance'] is Map<String, dynamic>
          ? json['appearance'] as Map<String, dynamic>
          : <String, dynamic>{},
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Versión segura: devuelve null y borra datos corruptos si el perfil no es válido (estructura plana)
  static Future<AiChanProfile?> tryFromJson(Map<String, dynamic> json) async {
    // Estructura esperada: todos los campos al mismo nivel
    final expectedKeys = [
      'userName',
      'aiName',
      'personality',
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
          json['personality'] is Map<String, dynamic> &&
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
    'personality': personality,
    'biography': biography,
    'appearance': appearance,
    'timeline': timeline.map((e) => e.toJson()).toList(),
    if (userBirthday != null)
      'userBirthday':
          "${userBirthday!.year.toString().padLeft(4, '0')}-${userBirthday!.month.toString().padLeft(2, '0')}-${userBirthday!.day.toString().padLeft(2, '0')}",
    if (aiBirthday != null)
      'aiBirthday':
          "${aiBirthday!.year.toString().padLeft(4, '0')}-${aiBirthday!.month.toString().padLeft(2, '0')}-${aiBirthday!.day.toString().padLeft(2, '0')}",
  };
}
