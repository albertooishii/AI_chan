// Barrel file: re-export canonical models directly.
export 'models/ai_chan_profile.dart';
export 'models/ai_response.dart';
export 'models/audio.dart';
export 'models/image.dart';
// Chat models migrated to chat/domain - re-export for cross-context access
export 'package:ai_chan/chat/domain/models/chat_event.dart';
export 'package:ai_chan/chat/domain/models/chat_export.dart';
// Message migrated to chat/domain - re-export for cross-context access
export 'package:ai_chan/chat/domain/models/message.dart';
// 🔥 ELIMINATED: models/realtime_provider.dart (was part of Call legacy system)
export 'models/system_prompt.dart';
export 'models/timeline_entry.dart';

// AI Provider models
export 'package:ai_chan/shared/ai_providers/core/models/voice_info.dart';

// Shared enums from kernel
export 'package:ai_chan/shared/domain/shared_enums.dart';
