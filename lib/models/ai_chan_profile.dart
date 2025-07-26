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
  final String? imageId;
  final String? imageBase64;
  final String? imageUrl; // New field added
  final String? revisedPrompt;

  AiChanProfile({
    required this.userName,
    required this.aiName,
    required this.userBirthday,
    required this.aiBirthday,
    required this.personality,
    required this.biography,
    required this.appearance,
    required this.timeline,
    this.imageId,
    this.imageBase64,
    this.imageUrl, // New field added to constructor
    this.revisedPrompt,
  });

  factory AiChanProfile.fromJson(Map<String, dynamic> json) {
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
      imageId: json['imageId'] as String?,
      imageBase64: json['imageBase64'] as String?,
      imageUrl: json['imageUrl'] as String?,
      revisedPrompt: json['revisedPrompt'] as String?,
    );
  }

  /// Versión segura: devuelve null y borra datos corruptos si el perfil no es válido (estructura plana)
  static Future<AiChanProfile?> tryFromJson(Map<String, dynamic> json) async {
    // Estructura esperada: todos los campos al mismo nivel
    final expectedKeys = ['userName', 'aiName', 'personality', 'biography', 'appearance', 'timeline'];
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
    'userBirthday': userBirthday != null
        ? "${userBirthday!.year.toString().padLeft(4, '0')}-${userBirthday!.month.toString().padLeft(2, '0')}-${userBirthday!.day.toString().padLeft(2, '0')}"
        : null,
    'aiBirthday': aiBirthday != null
        ? "${aiBirthday!.year.toString().padLeft(4, '0')}-${aiBirthday!.month.toString().padLeft(2, '0')}-${aiBirthday!.day.toString().padLeft(2, '0')}"
        : null,
    'personality': personality,
    'biography': biography,
    'appearance': appearance,
    'imageId': imageId,
    if (imageBase64?.isNotEmpty == true) 'imageBase64': imageBase64,
    'imageUrl': imageUrl, // New field added to JSON output
    'revisedPrompt': revisedPrompt,
    // timeline SIEMPRE debe ir al final para mantener el orden y evitar problemas de import/export
    'timeline': timeline.map((e) => e.toJson()).toList(),
  }..removeWhere((k, v) => v == null);

  AiChanProfile copyWith({
    String? userName,
    String? aiName,
    DateTime? userBirthday,
    DateTime? aiBirthday,
    Map<String, dynamic>? personality,
    Map<String, dynamic>? biography,
    Map<String, dynamic>? appearance,
    List<TimelineEntry>? timeline,
    String? imageId,
    String? imageBase64,
    String? imageUrl,
    String? revisedPrompt,
  }) {
    return AiChanProfile(
      userName: userName ?? this.userName,
      aiName: aiName ?? this.aiName,
      userBirthday: userBirthday ?? this.userBirthday,
      aiBirthday: aiBirthday ?? this.aiBirthday,
      personality: personality ?? this.personality,
      biography: biography ?? this.biography,
      appearance: appearance ?? this.appearance,
      timeline: timeline ?? this.timeline,
      imageId: imageId ?? this.imageId,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageUrl: imageUrl ?? this.imageUrl,
      revisedPrompt: revisedPrompt ?? this.revisedPrompt,
    );
  }
}
