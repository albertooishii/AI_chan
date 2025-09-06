import 'package:ai_chan/call/application/controllers/voice_call_screen_controller.dart';
import 'package:ai_chan/call/application/use_cases/start_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/end_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/handle_incoming_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/manage_audio_use_case.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_manager_adapter.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/application/interfaces/voice_call_controller_builder.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro

/// Implementación del builder para VoiceCallScreenController
class VoiceCallControllerBuilder implements IVoiceCallControllerBuilder {
  @override
  VoiceCallScreenController create({
    required final ChatController chatController,
    required final CallType callType,
  }) {
    // ✅ DDD: ETAPA 3 - DDD puro
    // Crear dependencias de infraestructura
    final aiService = di.getAIServiceForModel(Config.getDefaultTextModel());
    final callController = CallController(aiService: aiService);

    // Crear adapters
    final audioManager = AudioManagerAdapter(callController);
    final callManager = CallManagerAdapter(callController);

    // Crear use cases
    final startCallUseCase = StartCallUseCase(callManager);
    final endCallUseCase = EndCallUseCase(callManager);
    final handleIncomingCallUseCase = HandleIncomingCallUseCase(callManager);
    final manageAudioUseCase = ManageAudioUseCase(audioManager);

    // Crear controller con todas las dependencias
    return VoiceCallScreenController(
      chatController: chatController,
      callType: callType,
      startCallUseCase: startCallUseCase,
      endCallUseCase: endCallUseCase,
      handleIncomingCallUseCase: handleIncomingCallUseCase,
      manageAudioUseCase: manageAudioUseCase,
    );
  }
}
