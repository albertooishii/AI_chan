// Backward compatibility alias - EventEntry now points to ChatEvent
// This maintains compatibility while models migrate to their proper bounded contexts
import 'package:ai_chan/chat/domain/models/chat_event.dart';

// Re-export ChatEvent as EventEntry for backward compatibility
typedef EventEntry = ChatEvent;
