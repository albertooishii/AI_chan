// 🎯 Voice Bounded Context Barrel - DDD Architecture
// Nuevo sistema de voz implementando Domain-Driven Design

// Dominio
export 'voice/domain/entities/voice_session.dart';
export 'voice/domain/value_objects/voice_settings.dart';
export 'voice/domain/interfaces/voice_services.dart';
export 'voice/domain/interfaces/i_tone_service.dart';
export 'voice/domain/services/voice_session_orchestrator.dart';

// Aplicación
export 'voice/application/use_cases/manage_voice_session_use_case.dart';
export 'voice/application/services/voice_application_service.dart';
export 'voice/application/services/microphone_amplitude_service.dart';

// Infraestructura
export 'voice/infrastructure/services/dynamic_voice_services.dart';
export 'voice/infrastructure/services/tone_service.dart';

// Presentación
export 'voice/presentation/controllers/voice_controller.dart';
export 'voice/presentation/controllers/voice_call_controller.dart';
export 'voice/presentation/screens/voice_screen.dart';
