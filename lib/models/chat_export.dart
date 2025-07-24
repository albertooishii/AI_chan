import 'ai_chan_profile.dart';
import 'message.dart';

class ChatExport {
  final AiChanProfile profile;
  final List<Message> messages;

  ChatExport({required this.profile, required this.messages});

  Map<String, dynamic> toJson() {
    final map = profile.toJson();
    // Añade los mensajes al final
    return {...map, 'messages': messages.map((e) => e.toJson()).toList()};
  }

  factory ChatExport.fromJson(Map<String, dynamic> json) {
    // El perfil está al mismo nivel que los mensajes (estructura plana)
    final Map<String, dynamic> profileMap = Map.from(json);
    return ChatExport(
      profile: AiChanProfile.fromJson(profileMap),
      messages: (json['messages'] as List<dynamic>).map((e) => Message.fromJson(e)).toList(),
    );
  }
}
