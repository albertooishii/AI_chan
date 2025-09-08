import 'package:ai_chan/chat/domain/interfaces/i_chat_event_timeline_service.dart';
import 'package:ai_chan/shared/application/services/event_timeline_service.dart';

/// Infrastructure adapter implementing IChatEventTimelineService
/// Bridges the chat domain with shared event timeline services.
class ChatEventTimelineServiceAdapter implements IChatEventTimelineService {
  const ChatEventTimelineServiceAdapter();

  @override
  Future<dynamic> detectAndSaveEventAndSchedule({
    required final String text,
    required final String textResponse,
    required final dynamic onboardingData,
    required final Future<void> Function() saveAll,
  }) {
    return EventTimelineService.detectAndSaveEventAndSchedule(
      text: text,
      textResponse: textResponse,
      onboardingData: onboardingData,
      saveAll: saveAll,
    );
  }
}
