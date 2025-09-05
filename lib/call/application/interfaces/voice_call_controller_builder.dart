import 'package:ai_chan/call/application/controllers/voice_call_screen_controller.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';

/// Interfaz para construir VoiceCallScreenController
/// Esto permite que la capa de presentación obtenga un controller
/// sin importar infraestructura directamente
abstract class IVoiceCallControllerBuilder {
  VoiceCallScreenController create({
    required ChatProvider chatProvider,
    required CallType callType,
  });
}
