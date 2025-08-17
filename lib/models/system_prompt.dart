import 'dart:convert';
import '../models/ai_chan_profile.dart';

class SystemPrompt {
  final AiChanProfile profile;
  final DateTime dateTime;
  final List<Map<String, dynamic>>? recentMessages;

  /// Instrucciones ahora como objeto JSON (antes String codificado) para evitar doble codificación.
  final Map<String, dynamic> instructions;

  SystemPrompt({required this.profile, required this.dateTime, this.recentMessages, required this.instructions});

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    // Opción 1: asumimos siempre Map<String,dynamic> (sin soporte legacy String)
    return SystemPrompt(
      profile: AiChanProfile.fromJson(json['profile'] ?? {}),
      dateTime: DateTime.parse(json['dateTime'] ?? DateTime.now().toIso8601String()),
      recentMessages: json['recentMessages'] != null
          ? (json['recentMessages'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : null,
      instructions: json['instructions'] is Map
          ? Map<String, dynamic>.from(json['instructions'] as Map)
          : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
    'profile': profile.toJson(),
    'dateTime': dateTime.toIso8601String(),
    if (recentMessages != null && recentMessages!.isNotEmpty) 'recentMessages': recentMessages,
    'instructions': instructions,
  };

  @override
  String toString() => jsonEncode(toJson());
}
