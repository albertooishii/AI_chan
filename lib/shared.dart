// Shared Kernel Barrel Export
//
// This module contains the shared kernel - components that are used
// across multiple bounded contexts (Chat, Onboarding, Voice, etc.)

// Shared utilities commonly used
export 'shared/infrastructure/utils/date_utils.dart';
export 'shared/infrastructure/utils/locale_utils.dart';
export 'shared/infrastructure/utils/json_utils.dart';
export 'shared/infrastructure/utils/network_utils.dart';
export 'shared/infrastructure/utils/chat_json_utils.dart';
export 'shared/infrastructure/utils/onboarding_fallback_utils.dart';
export 'shared/infrastructure/services/ai_runtime_guard.dart';

// Domain utilities - Pure functions
export 'shared/domain/utils/schedule_utils.dart';

// Domain Layer - Models (migrated from core)
export 'shared/domain/models/index.dart';
export 'shared/domain/shared_enums.dart';
export 'shared/domain/models/voice_call_message.dart';

// Domain Interfaces (consolidated from core + existing)
export 'shared/domain/interfaces/index.dart';
export 'shared/domain/interfaces/i_navigation_service.dart';
export 'shared/domain/interfaces/i_shared_chat_repository.dart';
export 'shared/domain/interfaces/i_shared_backup_service.dart';
export 'shared/domain/interfaces/cross_context_interfaces.dart';
export 'shared/domain/interfaces/tts_service.dart';
export 'shared/domain/interfaces/i_stt_service.dart';
export 'shared/domain/interfaces/audio_recorder_service.dart';

// AI Providers - Audio models
export 'shared/ai_providers/core/models/audio/synthesis_result.dart';
export 'shared/ai_providers/core/models/audio/voice_settings.dart';

// Domain Enums
export 'shared/domain/enums/call_status.dart';
export 'shared/domain/enums/message_sender.dart';

// Voice domain enums (ConversationState moved here)
export 'voice/domain/interfaces/i_voice_conversation_service.dart'
    show ConversationState, ConversationStateExtension;

// Core Domain Communication (migrated from core)
export 'shared/domain/core_domain/interfaces/i_call_to_chat_communication_service.dart';

// Infrastructure Layer (migrated from core)
export 'shared/infrastructure/config/config.dart';
export 'shared/infrastructure/di/di.dart';
export 'shared/infrastructure/di/di_bootstrap.dart';
export 'shared/infrastructure/network/http_connector.dart';
export 'shared/infrastructure/network/network_connectors.dart';
export 'shared/infrastructure/cache/cache_service.dart';
export 'shared/infrastructure/services/firebase_init.dart';
export 'shared/ai_providers/core/utils/image/ai_image_factory.dart';
export 'shared/ai_providers/core/registry/provider_registration.dart';

// Application Layer
export 'shared/application/services/event_timeline_service.dart';
export 'shared/application/services/promise_service.dart';
export 'shared/application/services/audio_subtitle_application_service.dart';
export 'shared/application/services/cyberpunk_text_processor_service.dart'; // 🎮 CYBERPUNK!

// AI Generators (migrated from core)
export 'shared/application/services/ai_generators/ia_appearance_generator.dart';
export 'shared/application/services/ai_generators/ia_avatar_generator.dart';
export 'shared/application/services/ai_generators/ia_bio_generator.dart';
export 'shared/application/services/ai_generators/image_request_service.dart';
export 'shared/application/services/ai_generators/memory_summary_service.dart';

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
export 'shared/infrastructure/services/backup_service.dart';
export 'shared/infrastructure/services/google_appauth_adapter_desktop.dart';
export 'shared/infrastructure/services/basic_chat_audio_utils_service.dart';
export 'shared/infrastructure/services/basic_chat_debounced_persistence_service.dart';
export 'shared/infrastructure/services/basic_chat_logging_utils_service.dart';
export 'shared/infrastructure/services/basic_chat_message_queue_manager.dart';
export 'shared/infrastructure/services/basic_chat_preferences_utils_service.dart';
export 'shared/infrastructure/services/basic_chat_promise_service.dart';
export 'shared/infrastructure/services/basic_logging_service.dart';
export 'shared/infrastructure/services/basic_network_service.dart';
export 'shared/infrastructure/services/basic_preferences_service.dart';

// Infrastructure Repositories and Services - NEW IMPLEMENTATIONS
export 'shared/infrastructure/repositories/shared_chat_repository_impl.dart';
export 'shared/infrastructure/services/shared_backup_service_impl.dart';

// Infrastructure Adapters
export 'shared/infrastructure/adapters/cross_context_service_adapters.dart';
export 'shared/infrastructure/services/basic_recording_service.dart';
export 'shared/infrastructure/services/basic_secure_storage_service.dart';
export 'shared/infrastructure/services/basic_ui_state_listener.dart';
export 'shared/infrastructure/services/file_operations_service.dart';
export 'shared/infrastructure/services/file_service.dart';
export 'shared/infrastructure/services/navigation_service.dart';

// Infrastructure Adapters
export 'shared/infrastructure/adapters/audio_playback.dart';
export 'shared/infrastructure/adapters/file_operations_adapter.dart';
export 'shared/infrastructure/adapters/file_service_adapter.dart';
export 'shared/infrastructure/adapters/shared_logger_adapter.dart';
export 'shared/infrastructure/adapters/shared_profile_persistence_service_adapter.dart';

// Infrastructure Utils
export 'shared/infrastructure/utils/profile_persist_utils.dart';

// Shared Utils
export 'shared/infrastructure/utils/prefs_utils.dart';
export 'shared/infrastructure/utils/log_utils.dart';
export 'shared/infrastructure/utils/storage_utils.dart';
export 'shared/infrastructure/utils/string_utils.dart';
export 'shared/infrastructure/utils/streaming_subtitle_utils.dart';
export 'shared/infrastructure/utils/image/image_utils.dart';
export 'shared/infrastructure/utils/audio_duration_utils.dart';
export 'shared/infrastructure/utils/backup_auto_uploader.dart';
export 'shared/infrastructure/utils/backup_utils.dart';
export 'shared/infrastructure/utils/dialog_utils.dart';
export 'shared/infrastructure/utils/app_data_utils.dart';
export 'shared/infrastructure/utils/debug_call_logger/debug_call_logger_io.dart';
export 'shared/infrastructure/utils/shared_prompt_utils.dart';

// Presentation Layer
export 'shared/presentation/widgets/app_dialog.dart';
export 'shared/presentation/widgets/cyberpunk_subtitle.dart'; // 🎮 SUBTÍTULOS ÉPICOS!
export 'shared/presentation/widgets/cyberpunk_button.dart'; // 🎮 BOTÓN CYBERPUNK!

// Constants
export 'shared/constants.dart';
export 'shared/screens.dart';
export 'shared/utils.dart';

// Services - Active services only
export 'shared/infrastructure/services/voice_call_controller.dart';
export 'shared/infrastructure/services/google_backup_service.dart';
export 'shared/ai_providers/core/services/audio/hybrid_stt_service.dart';

// AI Providers System
export 'shared/ai_providers/core/interfaces/i_ai_provider.dart';
export 'shared/ai_providers/core/interfaces/i_tts_voice_provider.dart';
export 'shared/ai_providers/core/interfaces/i_cache_service.dart';
export 'shared/ai_providers/core/interfaces/i_http_connection_pool.dart';
export 'shared/ai_providers/core/interfaces/i_retry_service.dart';
export 'shared/ai_providers/core/interfaces/i_alert_service.dart';
export 'shared/ai_providers/core/models/ai_capability.dart';
export 'shared/ai_providers/core/models/ai_provider_config.dart';
export 'shared/ai_providers/core/models/ai_provider_metadata.dart';
export 'shared/ai_providers/core/models/provider_response.dart';
export 'shared/ai_providers/core/models/audio/voice_info.dart';
export 'shared/ai_providers/core/registry/ai_provider_registry.dart';
export 'shared/ai_providers/core/services/realtime_service.dart';
export 'shared/ai_providers/core/services/multi_model_router.dart';
export 'shared/ai_providers/core/services/ai_provider_manager.dart';
export 'shared/ai_providers/core/services/ai_provider_config_loader.dart';
export 'shared/ai_providers/core/services/ai_provider_factory.dart';
export 'shared/ai_providers/core/services/api_key_manager.dart';
export 'shared/ai_providers/core/services/in_memory_cache_service.dart';
export 'shared/ai_providers/core/services/performance_monitoring_service.dart';
export 'shared/ai_providers/core/services/request_deduplication_service.dart';
export 'shared/ai_providers/core/services/http_connection_pool.dart';
export 'shared/ai_providers/core/services/intelligent_retry_service.dart';
export 'shared/ai_providers/core/services/provider_alert_service.dart';
export 'shared/ai_providers/core/services/image/image_persistence_service.dart';
export 'shared/ai_providers/core/services/audio/audio_persistence_service.dart';
export 'shared/ai_providers/core/audio_services.dart';
