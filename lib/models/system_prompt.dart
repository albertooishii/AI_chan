import 'dart:convert';
import '../models/ai_chan_profile.dart';
import '../models/timeline_entry.dart';

class SystemPrompt {
  final AiChanProfile profile;
  final DateTime dateTime;
  final List<TimelineEntry> timeline;
  final List<Map<String, dynamic>> recentMessages;
  final String instructions;

  SystemPrompt({
    required this.profile,
    required this.dateTime,
    required this.timeline,
    required this.recentMessages,
    required this.instructions,
  });

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(
      profile: AiChanProfile.fromJson(json['profile'] ?? {}),
      dateTime: DateTime.parse(json['dateTime'] ?? DateTime.now().toIso8601String()),
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentMessages: (json['recentMessages'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      instructions: json['instructions'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'profile': profile.toJson(),
    'dateTime': dateTime.toIso8601String(),
    'timeline': timeline.map((e) => e.toJson()).toList(),
    'recentMessages': recentMessages,
    'instructions': instructions,
  };

  @override
  String toString() => jsonEncode(toJson());
}
