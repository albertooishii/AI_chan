import 'package:ai_chan/call/presentation/controllers/voice_call_screen_controller.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro

/// Interfaz para construir VoiceCallScreenController
/// Esto permite que la capa de presentación obtenga un controller
/// sin importar infraestructura directamente
abstract class IVoiceCallControllerBuilder {
  VoiceCallScreenController create({
    required final IChatController chatController, // ✅ DDD: ETAPA 3 - DDD puro
    required final CallType callType,
  });
}
