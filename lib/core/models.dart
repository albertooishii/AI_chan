// Barrel file: re-export canonical models directly.
export 'models/ai_chan_profile.dart';
export 'models/ai_response.dart';
export '../chat/domain/models/chat_export.dart'; // ChatExport moved to chat domain
export 'models/image.dart';
// Chat models migrated to chat/domain - re-export for compatibility
export 'package:ai_chan/chat/domain/models/chat_event.dart';
// EventEntry alias for backward compatibility
export 'models/event_entry.dart';
// ImportedChat consolidation - use core version
export 'models/imported_chat.dart';
// Message migrated to chat/domain - re-export for compatibility
export 'package:ai_chan/chat/domain/models/message.dart';
export 'models/realtime_provider.dart';
export 'models/system_prompt.dart';
export 'models/timeline_entry.dart';

// Shared enums from kernel
export 'package:ai_chan/shared/domain/shared_enums.dart';
