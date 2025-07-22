import 'ai_chan_profile.dart';
import 'message.dart';

/// Modelo robusto para importar/exportar un chat completo (biografía + mensajes)
class ImportedChat {
  final AiChanProfile biography;
  final List<Message> messages;

  ImportedChat({required this.biography, required this.messages});

  factory ImportedChat.fromJson(Map<String, dynamic> json) {
    return ImportedChat(
      biography: AiChanProfile.fromJson(
        json['biography'] as Map<String, dynamic>,
      ),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((e) => Message.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'biography': biography.toJson(),
    'messages': messages.map((e) => e.toJson()).toList(),
  };
}
