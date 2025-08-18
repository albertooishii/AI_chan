import 'package:ai_chan/core/models/ai_chan_profile.dart';
import 'package:ai_chan/core/models/message.dart';
import 'package:ai_chan/core/models/event_entry.dart';

class ChatExport {
  final AiChanProfile profile;
  final List<Message> messages;
  final List<EventEntry> events;

  ChatExport({required this.profile, required this.messages, required this.events});

  Map<String, dynamic> toJson() {
    final map = profile.toJson();
    return {
      ...map,
      'messages': messages.map((e) => e.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatExport.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profileMap = Map.from(json);
    return ChatExport(
      profile: AiChanProfile.fromJson(profileMap),
      messages: (json['messages'] as List<dynamic>).map((e) => Message.fromJson(e)).toList(),
      events: (json['events'] as List<dynamic>? ?? []).map((e) => EventEntry.fromJson(e)).toList(),
    );
  }
}
