// Shared Domain Models - Kernel Compartido
export 'ai_chan_profile.dart';
export 'audio.dart';
export 'image.dart';
export 'system_prompt.dart';
export 'timeline_entry.dart';
export 'voice_call_message.dart';

// Core domain models (shared across all bounded contexts)
export 'message.dart';
export 'chat_event.dart';
export 'chat_export.dart';

// Re-export shared enums
export 'package:ai_chan/shared/domain/enums/message_sender.dart';
export 'package:ai_chan/shared/domain/shared_enums.dart';

// Re-export AIResponse from ai_providers
export 'package:ai_chan/shared/ai_providers/core/models/ai_response.dart';

// Re-export AI Provider models
export 'package:ai_chan/shared/ai_providers/core/models/audio/voice_info.dart';
