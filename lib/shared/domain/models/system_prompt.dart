import 'dart:convert';
import 'package:ai_chan/shared/domain/models/ai_chan_profile.dart';

class SystemPrompt {
  SystemPrompt({
    required this.profile,
    required this.dateTime,
    this.recentMessages,
    required this.instructions,
  });

  factory SystemPrompt.fromJson(final Map<String, dynamic> json) {
    // Opcif3n 1: asumimos siempre Map<String,dynamic> (sin soporte legacy String)
    return SystemPrompt(
      profile: AiChanProfile.fromJson(json['profile'] ?? {}),
      dateTime: DateTime.parse(
        json['dateTime'] ?? DateTime.now().toIso8601String(),
      ),
      recentMessages: json['recentMessages'] != null
          ? (json['recentMessages'] as List<dynamic>)
                .map((final e) => Map<String, dynamic>.from(e as Map))
                .toList()
          : null,
      instructions: json['instructions'] is Map
          ? Map<String, dynamic>.from(json['instructions'] as Map)
          : <String, dynamic>{},
    );
  }
  final AiChanProfile profile;
  final DateTime dateTime;
  final List<Map<String, dynamic>>? recentMessages;

  /// Instrucciones ahora como objeto JSON (antes String codificado) para evitar doble codificacif3n.
  final Map<String, dynamic> instructions;

  Map<String, dynamic> toJson() => {
    'profile': profile.toJson(),
    'dateTime': dateTime.toIso8601String(),
    if (recentMessages != null && recentMessages!.isNotEmpty)
      'recentMessages': recentMessages,
    'instructions': instructions,
  };

  @override
  String toString() => jsonEncode(toJson());
}
