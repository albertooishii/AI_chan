// Barrel file: re-export canonical models directly.
export 'models/ai_chan_profile.dart';
export 'models/ai_response.dart';
export 'models/chat_export.dart';
// Chat models migrated to chat/domain - re-export for compatibility
export 'package:ai_chan/chat/domain/models/chat_event.dart';
// EventEntry alias for backward compatibility
export 'models/event_entry.dart';
export 'models/image.dart';
export 'models/imported_chat.dart';
// Message migrated to chat/domain - re-export for compatibility
export 'package:ai_chan/chat/domain/models/message.dart';
export 'models/realtime_provider.dart';
export 'models/system_prompt.dart';
export 'models/timeline_entry.dart';
export 'models/unified_audio_config.dart';

// Shared enums from kernel
export 'package:ai_chan/shared/domain/shared_enums.dart';
