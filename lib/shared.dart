// Shared Kernel Barrel Export
//
// This module contains the shared kernel - components that are used
// across multiple bounded contexts (Chat, Onboarding, Voice, etc.)

// Domain Layer
export 'shared/domain/shared_enums.dart';
export 'shared/domain/models/voice_call_message.dart';

// Domain Interfaces
export 'shared/domain/interfaces/audio_playback_service.dart';
export 'shared/domain/interfaces/i_ai_service.dart';
export 'shared/domain/interfaces/i_file_operations_service.dart';
export 'shared/domain/interfaces/i_file_service.dart';
export 'shared/domain/interfaces/i_profile_persistence_service.dart';
export 'shared/domain/interfaces/i_recording_service.dart';
export 'shared/domain/interfaces/i_shared_logger.dart';
export 'shared/domain/interfaces/i_ui_state_service.dart';

// Domain Enums
export 'shared/domain/enums/call_status.dart';
export 'shared/domain/enums/message_sender.dart';
export 'shared/domain/enums/conversation_state.dart';

// Application Layer
export 'shared/application/services/event_timeline_service.dart';
export 'shared/application/services/promise_service.dart';
export 'shared/application/services/audio_subtitle_application_service.dart';
export 'shared/application/services/cyberpunk_text_processor_service.dart'; // 🎮 CYBERPUNK!

// Additional Application Services
export 'shared/application/services/calendar_processing_service.dart';
export 'shared/application/services/file_ui_service.dart';

// Infrastructure Layer
export 'shared/infrastructure/services/flutter_secure_storage_service.dart';
export 'shared/infrastructure/services/basic_ui_state_service.dart';
export 'shared/infrastructure/services/basic_file_operations_service.dart';
export 'shared/infrastructure/services/real_preferences_service.dart';

// Additional Infrastructure Services
export 'shared/infrastructure/services/basic_backup_service.dart';
export 'shared/infrastructure/services/basic_chat_audio_utils_service.dart';
export 'shared/infrastructure/services/basic_chat_debounced_persistence_service.dart';
export 'shared/infrastructure/services/basic_chat_logging_utils_service.dart';
export 'shared/infrastructure/services/basic_chat_message_queue_manager.dart';
export 'shared/infrastructure/services/basic_chat_preferences_utils_service.dart';
export 'shared/infrastructure/services/basic_chat_promise_service.dart';
export 'shared/infrastructure/services/basic_logging_service.dart';
export 'shared/infrastructure/services/basic_network_service.dart';
export 'shared/infrastructure/services/basic_preferences_service.dart';

// Infrastructure Adapters
export 'shared/infrastructure/adapters/cross_context_service_adapters.dart';
export 'shared/infrastructure/services/basic_recording_service.dart';
export 'shared/infrastructure/services/basic_secure_storage_service.dart';
export 'shared/infrastructure/services/basic_ui_state_listener.dart';
export 'shared/infrastructure/services/file_operations_service.dart';
export 'shared/infrastructure/services/file_service.dart';

// Infrastructure Adapters
export 'shared/infrastructure/adapters/audio_playback.dart';
export 'shared/infrastructure/adapters/file_operations_adapter.dart';
export 'shared/infrastructure/adapters/file_service_adapter.dart';
export 'shared/infrastructure/adapters/shared_logger_adapter.dart';
export 'shared/infrastructure/adapters/shared_profile_persistence_service_adapter.dart';

// Infrastructure Utils
export 'shared/infrastructure/utils/profile_persist_utils.dart';

// Shared Utils
export 'shared/utils/prefs_utils.dart';
export 'shared/utils/log_utils.dart';
export 'shared/utils/audio_duration_utils.dart';
export 'shared/utils/backup_auto_uploader.dart';
export 'shared/utils/chat_json_utils.dart';
export 'shared/utils/dialog_utils.dart';
export 'shared/utils/app_data_utils.dart';

// Widgets
export 'shared/widgets/app_dialog.dart';
export 'shared/presentation/widgets/cyberpunk_subtitle.dart'; // 🎮 SUBTÍTULOS ÉPICOS!

// Constants
export 'shared/constants.dart';
export 'shared/screens.dart';
export 'shared/utils.dart';

// Services - Active services only
export 'shared/services/voice_call_controller.dart';
export 'shared/services/google_backup_service.dart';
export 'shared/services/hybrid_stt_service.dart';

// AI Providers System
export 'shared/ai_providers/core/interfaces/i_ai_provider.dart';
export 'shared/ai_providers/core/registry/ai_provider_registry.dart';
export 'shared/ai_providers/core/services/realtime_service.dart';
export 'shared/ai_providers/core/services/multi_model_router.dart';
export 'shared/ai_providers/audio_services.dart';
