// Call Bounded Context Barrel Export

// Domain Layer
export 'call/domain/models/audio_format.dart';
export 'call/domain/models/call.dart';
export 'call/domain/models/call_message.dart';
export 'call/domain/models/call_provider.dart';
export 'call/domain/services/call_service.dart';
export 'call/domain/services/call_summary_service.dart';

// Domain Interfaces
export 'call/domain/interfaces/audio_scheduling_service.dart';
export 'call/domain/interfaces/call_interfaces.dart';
export 'call/domain/interfaces/i_audio_playback_strategy.dart';
export 'call/domain/interfaces/i_call_message.dart';
export 'call/domain/interfaces/i_chat_integration_service.dart';
export 'call/domain/interfaces/i_google_speech_service.dart';
export 'call/domain/interfaces/i_speech_service.dart';
export 'call/domain/interfaces/i_tone_service.dart';
export 'call/domain/interfaces/i_vad_service.dart';
export 'call/domain/interfaces/realtime_transport_service.dart';

// Domain Entities
export 'call/domain/entities/voice_call_message.dart';
export 'call/domain/entities/voice_call_state.dart';

// Application Layer
export 'call/application/services/call_state_application_service.dart';
export 'call/application/use_cases/manage_voice_call_config_use_case.dart';
export 'call/application/use_cases/process_assistant_response_use_case.dart';
export 'call/application/use_cases/get_voice_call_history_use_case.dart';
export 'call/application/use_cases/process_user_audio_use_case.dart';

// Additional Application Services
export 'call/application/services/call_application_service.dart';
export 'call/application/services/call_playback_application_service.dart';
export 'call/application/services/call_recording_application_service.dart';
export 'call/application/services/cyberpunk_text_processor_service.dart';
export 'call/application/services/voice_call_application_service.dart';

// Additional Application Use Cases
export 'call/application/use_cases/end_call_use_case.dart';
export 'call/application/use_cases/handle_incoming_call_use_case.dart';
export 'call/application/use_cases/manage_audio_use_case.dart';
export 'call/application/use_cases/start_call_use_case.dart';

// Infrastructure Layer
export 'call/infrastructure/adapters/openai_realtime_call_client.dart';
export 'call/infrastructure/services/android_native_tts_service.dart';
export 'call/infrastructure/services/google_speech_service.dart';
export 'call/infrastructure/services/openai_speech_service.dart';

// Infrastructure Adapters
export 'call/infrastructure/adapters/android_native_stt_adapter.dart';
export 'call/infrastructure/adapters/android_native_tts_adapter.dart';
export 'call/infrastructure/adapters/audio_playback_strategy.dart';
export 'call/infrastructure/adapters/audio_playback_strategy_factory.dart';
export 'call/infrastructure/adapters/call_message_adapter.dart';
export 'call/infrastructure/adapters/call_strategy.dart';
export 'call/infrastructure/adapters/chat_integration_service_adapter.dart';
export 'call/infrastructure/adapters/default_call_manager.dart';
export 'call/infrastructure/adapters/default_tts_service.dart';
export 'call/infrastructure/adapters/flutter_audio_manager.dart';
export 'call/infrastructure/adapters/google_speech_adapter.dart';
export 'call/infrastructure/adapters/google_speech_service_adapter.dart';
export 'call/infrastructure/adapters/google_stt_adapter.dart';
export 'call/infrastructure/adapters/google_tts_adapter.dart';
export 'call/infrastructure/adapters/in_memory_call_repository.dart';
export 'call/infrastructure/adapters/openai_speech_service_adapter.dart';
export 'call/infrastructure/adapters/openai_stt_adapter.dart';
export 'call/infrastructure/adapters/openai_tts_adapter.dart';
export 'call/infrastructure/adapters/tone_service.dart';
export 'call/infrastructure/adapters/websocket_realtime_transport_service.dart';

// Additional Infrastructure Services
export 'call/infrastructure/services/gemini_realtime_client.dart';
export 'call/infrastructure/services/openai_realtime_client.dart';

// Infrastructure Managers
export 'call/infrastructure/managers/audio_manager_impl.dart';
export 'call/infrastructure/managers/call_manager_impl.dart';

// Infrastructure Repositories
export 'call/infrastructure/repositories/local_call_repository.dart';

// Infrastructure Transport
export 'call/infrastructure/transport/openai_transport.dart';
export 'call/infrastructure/transport/realtime_transport.dart';

// Infrastructure Utils
export 'call/infrastructure/vad_service.dart';
export 'call/infrastructure/voice_utils.dart';

// Presentation Layer

// Controllers - NOW HERE! ✅
export 'call/presentation/controllers/call_controller.dart';
export 'call/presentation/controllers/voice_call_screen_controller.dart';
export 'call/presentation/controllers/_call_audio_controller.dart';
export 'call/presentation/controllers/_call_playback_controller.dart';
export 'call/presentation/controllers/_call_recording_controller.dart';
export 'call/presentation/controllers/_call_state_controller.dart';
export 'call/presentation/controllers/_call_ui_controller.dart';

// Screens
export 'call/presentation/screens/voice_call_screen.dart';

// Widgets
export 'call/presentation/widgets/cyberpunk_painters.dart';
export 'call/presentation/widgets/cyberpunk_subtitle.dart';
