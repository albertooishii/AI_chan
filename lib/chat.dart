// Chat Bounded Context Barrel Export

// Domain Layer
export 'chat/domain/models/chat_conversation.dart';
export 'chat/domain/models/chat_queued_send_options.dart';
export 'chat/domain/models/chat_result.dart';
export 'chat/domain/services/periodic_ia_message_scheduler.dart';

// Domain Interfaces
export 'chat/domain/interfaces/i_audio_chat_service.dart';
export 'chat/domain/interfaces/i_chat_avatar_service.dart';
export 'chat/domain/interfaces/i_chat_controller.dart';
export 'chat/domain/interfaces/i_chat_debounced_persistence_service.dart';
export 'chat/domain/interfaces/i_chat_event_timeline_service.dart';
export 'chat/domain/interfaces/i_chat_file_operations_service.dart';
export 'chat/domain/interfaces/i_chat_image_service.dart';
export 'chat/domain/interfaces/i_chat_logging_utils_service.dart';
export 'chat/domain/interfaces/i_chat_message_queue_manager.dart';
export 'chat/domain/interfaces/i_chat_preferences_service.dart';
export 'chat/domain/interfaces/i_chat_preferences_utils_service.dart';
export 'chat/domain/interfaces/i_chat_profile_persistence_service.dart';
export 'chat/domain/interfaces/i_chat_repository.dart';
export 'chat/domain/interfaces/i_language_resolver.dart';
export 'chat/domain/interfaces/i_prompt_builder_service.dart';
export 'chat/domain/interfaces/i_secure_storage_service.dart';

// Application Layer
export 'chat/application/services/chat_application_service.dart';
export 'chat/application/services/debounced_save.dart';
export 'chat/application/services/memory_manager.dart';
export 'chat/application/services/message_audio_processing_service.dart';
export 'chat/application/services/message_image_processing_service.dart';
export 'chat/application/services/message_queue_manager.dart';
export 'chat/application/services/message_retry_service.dart';
export 'chat/application/services/message_sanitization_service.dart';
export 'chat/application/services/message_text_processor_service.dart';
export 'shared/ai_providers/core/services/audio/tts_service.dart';
export 'chat/application/services/tts_voice_service.dart';

// Application Main File
// export 'chat/application/chat_application.dart'; // Removed - consolidated

// Application Use Cases
export 'chat/application/use_cases/send_message_use_case.dart';
export 'chat/application/use_cases/load_chat_history_use_case.dart';
export 'chat/application/use_cases/export_chat_use_case.dart';
export 'chat/application/use_cases/import_chat_use_case.dart';

// Application Adapters
export 'chat/application/adapters/call_to_chat_communication_adapter.dart';

// Application Utils
// NOTE: avatar persistence utilities moved to shared/image/image_profile_utils.dart

// Infrastructure Layer
export 'shared/ai_providers/core/adapters/chat_ai_service_adapter.dart';
export 'chat/infrastructure/adapters/local_chat_repository.dart';
export 'shared/ai_providers/core/services/audio/audio_chat_service.dart';
export 'chat/infrastructure/adapters/language_resolver_service.dart';
export 'chat/infrastructure/adapters/prompt_builder_service.dart';
export 'chat/infrastructure/adapters/tts_voice_management_service_adapter.dart';

// Additional Infrastructure Adapters
export 'chat/infrastructure/adapters/chat_avatar_service_adapter.dart';
export 'chat/infrastructure/adapters/chat_controller_adapter.dart';

// Infrastructure Services
export 'chat/infrastructure/services/basic_chat_file_operations_service.dart';

// Infrastructure Persistence
export 'chat/infrastructure/persistence/chat_profile_persistence_service_adapter.dart';

// Infrastructure Preferences
export 'chat/infrastructure/preferences/chat_preferences_service_adapter.dart';

// Infrastructure Logging

// Infrastructure Events
export 'chat/infrastructure/events/chat_event_timeline_service_adapter.dart';

// Infrastructure Image
export 'chat/infrastructure/image/chat_image_service_adapter.dart';

// Presentation Layer
export 'chat/presentation/screens/chat_screen.dart';
export 'chat/presentation/screens/gallery_screen.dart';
export 'chat/presentation/widgets/chat_bubble.dart';
export 'chat/presentation/widgets/message_input.dart';
export 'chat/presentation/widgets/tts_configuration_dialog.dart';

// Additional Application Services (from chat_application.dart)
export 'chat/presentation/controllers/chat_controller.dart';
