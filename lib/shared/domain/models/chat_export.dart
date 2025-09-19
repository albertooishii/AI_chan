import 'package:ai_chan/shared/domain/models/ai_chan_profile.dart';
import 'package:ai_chan/shared/domain/models/message.dart';
import 'package:ai_chan/shared/domain/models/chat_event.dart';
import 'package:ai_chan/shared/domain/models/timeline_entry.dart';

class ChatExport {
  ChatExport({
    required this.profile,
    required this.messages,
    required this.events,
    required this.timeline,
  });

  factory ChatExport.fromJson(final Map<String, dynamic> json) {
    final Map<String, dynamic> profileMap = Map.from(json);
    return ChatExport(
      profile: AiChanProfile.fromJson(profileMap),
      messages: (json['messages'] as List<dynamic>)
          .map((final e) => Message.fromJson(e))
          .toList(),
      events: (json['events'] as List<dynamic>? ?? [])
          .map((final e) => ChatEvent.fromJson(e))
          .toList(),
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .map((final e) => TimelineEntry.fromJson(e))
          .toList(),
    );
  }
  final AiChanProfile profile;
  final List<Message> messages;
  final List<ChatEvent> events;
  final List<TimelineEntry> timeline;

  Map<String, dynamic> toJson() {
    final map = profile.toJson();
    return {
      ...map,
      'messages': messages.map((final e) => e.toJson()).toList(),
      'events': events.map((final e) => e.toJson()).toList(),
      'timeline': timeline.map((final e) => e.toJson()).toList(),
    };
  }
}
