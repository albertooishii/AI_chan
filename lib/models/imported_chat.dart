import 'ai_chan_profile.dart';
import 'message.dart';

/// Modelo robusto para importar/exportar un chat completo (perfil plano + mensajes)
class ImportedChat {
  final AiChanProfile profile;
  final List<Message> messages;

  ImportedChat({required this.profile, required this.messages});

  factory ImportedChat.fromJson(Map<String, dynamic> json) {
    // El perfil está al mismo nivel que los mensajes (estructura plana)
    final Map<String, dynamic> profileMap = Map.from(json);
    profileMap.remove('messages');
    return ImportedChat(
      profile: AiChanProfile.fromJson(profileMap),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((e) => Message.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = profile.toJson();
    map['messages'] = messages.map((e) => e.toJson()).toList();
    return map;
  }
}
