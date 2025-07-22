import 'timeline_entry.dart';

class AiChanProfile {
  final Map<String, dynamic> personality;
  final Map<String, dynamic> biography;
  final List<TimelineEntry> timeline;
  final String userName;
  final String aiName;
  final DateTime? userBirthday;
  final DateTime? aiBirthday;
  final Map<String, dynamic> appearance;

  AiChanProfile({
    required this.personality,
    required this.biography,
    required this.timeline,
    required this.userName,
    required this.aiName,
    required this.userBirthday,
    required this.aiBirthday,
    required this.appearance,
  });

  factory AiChanProfile.fromJson(Map<String, dynamic> json) {
    if (json['userName'] == null ||
        json['userName'] is! String ||
        (json['userName'] as String).isEmpty) {
      throw Exception(
        'El campo userName es obligatorio y debe ser un String no vacío.',
      );
    }
    if (json['aiName'] == null ||
        json['aiName'] is! String ||
        (json['aiName'] as String).isEmpty) {
      throw Exception(
        'El campo aiName es obligatorio y debe ser un String no vacío.',
      );
    }
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
    final appearanceMap = (json['appearance'] is Map<String, dynamic>)
        ? (json['appearance'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final biographyMap = (json['biography'] is Map<String, dynamic>)
        ? (json['biography'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final personalityMap = (json['personality'] is Map<String, dynamic>)
        ? (json['personality'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return AiChanProfile(
      personality: personalityMap,
      biography: biographyMap,
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      userName: json['userName'],
      aiName: json['aiName'],
      userBirthday: birth,
      aiBirthday: aiBirth,
      appearance: appearanceMap,
    );
  }

  Map<String, dynamic> toJson() => {
    'personality': personality,
    'biography': biography,
    'timeline': timeline.map((e) => e.toJson()).toList(),
    'userName': userName,
    'aiName': aiName,
    if (userBirthday != null)
      'userBirthday':
          "${userBirthday!.year.toString().padLeft(4, '0')}-${userBirthday!.month.toString().padLeft(2, '0')}-${userBirthday!.day.toString().padLeft(2, '0')}",
    if (aiBirthday != null)
      'aiBirthday':
          "${aiBirthday!.year.toString().padLeft(4, '0')}-${aiBirthday!.month.toString().padLeft(2, '0')}-${aiBirthday!.day.toString().padLeft(2, '0')}",
    'appearance': appearance,
    // meetStory ya está en timeline, no se exporta duplicado
  };
}
