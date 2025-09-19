// Shared Domain Interfaces - Kernel Compartido

// Interfaces migradas desde core
export 'i_native_tts_service.dart';
export '../../ai_providers/core/interfaces/i_openai_speech_service.dart';
export 'i_profile_service.dart';
export '../../ai_providers/core/interfaces/i_realtime_client.dart';
export 'i_stt_service.dart';
export 'tts_service.dart';

// Interfaces existentes en shared
export 'audio_playback_service.dart';
export 'i_file_operations_service.dart';
export 'i_file_service.dart';
export 'i_recording_service.dart';
export 'i_ui_state_service.dart';

// Re-export AI service from ai_providers
export 'i_ai_service.dart';
