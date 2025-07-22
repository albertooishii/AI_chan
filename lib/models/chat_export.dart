import 'ai_chan_profile.dart';
import 'message.dart';

class ChatExport {
  final AiChanProfile biography;
  final List<Message> messages;

  ChatExport({required this.biography, required this.messages});

  Map<String, dynamic> toJson() {
    return {
      'biography': biography.toJson(),
      'messages': messages.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatExport.fromJson(Map<String, dynamic> json) {
    final bioJson = json['biography'] ?? {};
    return ChatExport(
      biography: AiChanProfile.fromJson(bioJson),
      messages: (json['messages'] as List<dynamic>)
          .map((e) => Message.fromJson(e))
          .toList(),
    );
  }
}
