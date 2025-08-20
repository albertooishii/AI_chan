import 'package:ai_chan/core/models/ai_chan_profile.dart';
import 'message.dart';
import 'package:ai_chan/core/models/event_entry.dart';

/// Modelo robusto para importar/exportar un chat completo (perfil plano + mensajes)
class ImportedChat {
  final AiChanProfile profile;
  final List<Message> messages;
  final List<EventEntry> events;

  ImportedChat({
    required this.profile,
    required this.messages,
    required this.events,
  });

  factory ImportedChat.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profileMap = Map.from(json);
    profileMap.remove('messages');
    profileMap.remove('events');
    return ImportedChat(
      profile: AiChanProfile.fromJson(profileMap),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((e) => Message.fromJson(e))
          .toList(),
      events: (json['events'] as List<dynamic>? ?? [])
          .map((e) => EventEntry.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = profile.toJson();
    map['messages'] = messages.map((e) => e.toJson()).toList();
    map['events'] = events.map((e) => e.toJson()).toList();
    return map;
  }
}
