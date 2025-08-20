// Shared Kernel Barrel Export
// Generated as part of DDD + Hexagonal Architecture migration
//
// This module contains the shared kernel - components that are used
// across multiple bounded contexts (Chat, Onboarding, Voice, etc.)

export 'shared/constants.dart';
export 'shared/utils.dart';
export 'shared/widgets.dart';
export 'shared/screens.dart';
export 'shared/domain/shared_enums.dart';
export 'shared/domain/services/event_timeline_service.dart';
export 'shared/domain/services/promise_service.dart';

// Legacy services moved to shared (to be refactored)
export 'shared/services/ai_service.dart';
export 'shared/services/google_speech_service.dart';
export 'shared/services/android_native_tts_service.dart';
export 'shared/services/cache_service.dart';
export 'shared/services/event_service.dart';
export 'shared/services/promise_service.dart';
export 'shared/services/subtitle_controller.dart';
export 'shared/services/voice_call_controller.dart';
export 'shared/services/gemini_service.dart';
export 'shared/services/openai_service.dart';
