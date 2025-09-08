/// Mensaje de voz dentro de una llamada
/// Modelo compartido entre los contextos de chat y call
class VoiceCallMessage {
  VoiceCallMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  factory VoiceCallMessage.fromJson(final Map<String, dynamic> json) {
    return VoiceCallMessage(
      text: json['text'] ?? '',
      isUser: json['isUser'] == true,
      timestamp: json['timestamp'] != null && json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String text;
  final bool isUser;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
  };
}
