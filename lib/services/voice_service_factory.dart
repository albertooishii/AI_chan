import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../interfaces/voice_services.dart';
import 'implementations/google_speech_implementations.dart';
import 'implementations/gemini_conversational_service.dart';
import 'google_voice_call_service.dart';
import '../models/realtime_provider.dart';
import '../utils/log_utils.dart';

/// Factory para crear servicios de voz según la configuración
class VoiceServiceFactory {
  /// Crea un servicio de llamadas de voz según el proveedor configurado
  static VoiceCallService createVoiceCallService({RealtimeProvider? provider}) {
    final selectedProvider = provider ?? _getConfiguredProvider();

    Log.i('[VoiceFactory] 🏭 Creando servicio de voz para: ${selectedProvider.name}');

    switch (selectedProvider) {
      case RealtimeProvider.gemini:
        return _createGoogleVoiceService();
      case RealtimeProvider.openai:
        throw UnimplementedError('OpenAI VoiceCallService aún no implementado en el factory');
    }
  }

  /// Crea servicio TTS según configuración
  static TTSService createTTSService() {
    final ttsMode = dotenv.env['AUDIO_TTS_MODE']?.toLowerCase() ?? 'google';

    Log.i('[VoiceFactory] 🎵 Creando servicio TTS: $ttsMode');

    switch (ttsMode) {
      case 'google':
        return GoogleTTSService();
      default:
        Log.w('[VoiceFactory] TTS mode "$ttsMode" no reconocido, usando Google por defecto');
        return GoogleTTSService();
    }
  }

  /// Crea servicio STT según configuración
  static STTService createSTTService() {
    final sttMode = dotenv.env['AUDIO_STT_MODE']?.toLowerCase() ?? 'google';

    Log.i('[VoiceFactory] 🎤 Creando servicio STT: $sttMode');

    switch (sttMode) {
      case 'google':
        return GoogleSTTService();
      default:
        Log.w('[VoiceFactory] STT mode "$sttMode" no reconocido, usando Google por defecto');
        return GoogleSTTService();
    }
  }

  /// Crea servicio de IA conversacional según configuración
  static ConversationalAIService createConversationalAIService() {
    final provider = _getConfiguredProvider();

    Log.i('[VoiceFactory] 🤖 Creando servicio de IA: ${provider.name}');

    switch (provider) {
      case RealtimeProvider.gemini:
        return GeminiConversationalAIService();
      case RealtimeProvider.openai:
        throw UnimplementedError('OpenAI ConversationalAIService aún no implementado');
    }
  }

  /// Crea servicio completo de Google Voice (Gemini AI + Google Cloud TTS/STT)
  static GoogleVoiceCallService _createGoogleVoiceService() {
    Log.i('[VoiceFactory] 🚀 Creando Google Voice Service: Gemini AI + Google Cloud TTS/STT');

    return GoogleVoiceCallService(
      ttsService: createTTSService(),
      sttService: createSTTService(),
      aiService: createConversationalAIService(),
    );
  }

  /// Obtiene el proveedor configurado desde variables de entorno
  static RealtimeProvider _getConfiguredProvider() {
    final audioProvider = dotenv.env['AUDIO_PROVIDER']?.toLowerCase() ?? 'gemini';
    return RealtimeProviderHelper.fromString(audioProvider);
  }

  /// Verifica si el servicio de Google Voice está disponible
  static bool isGoogleVoiceServiceAvailable() {
    final provider = _getConfiguredProvider();
    final ttsMode = dotenv.env['AUDIO_TTS_MODE']?.toLowerCase() ?? 'google';

    Log.d('[VoiceFactory] 🔍 Verificando disponibilidad del servicio Google Voice');
    Log.d('  Provider: ${provider.name}');
    Log.d('  TTS Mode: $ttsMode');

    // Soportamos Gemini + Google TTS/STT
    final isSupported = provider == RealtimeProvider.gemini && ttsMode == 'google';

    if (isSupported) {
      // Verificar que todos los servicios estén configurados
      final ttsService = createTTSService();
      final sttService = createSTTService();
      final aiService = createConversationalAIService();

      final allAvailable = ttsService.isAvailable && sttService.isAvailable && aiService.isAvailable;

      Log.i(
        '[VoiceFactory] ✅ Google Voice Service ${allAvailable ? 'disponible' : 'no disponible (servicios no configurados)'}',
      );
      return allAvailable;
    } else {
      Log.w('[VoiceFactory] ⚠️ Configuración no soportada para Google Voice Service');
      return false;
    }
  }

  /// Obtiene información de configuración actual
  static Map<String, dynamic> getConfigInfo() {
    final provider = _getConfiguredProvider();
    final ttsMode = dotenv.env['AUDIO_TTS_MODE']?.toLowerCase() ?? 'google';
    final sttMode = dotenv.env['AUDIO_STT_MODE']?.toLowerCase() ?? 'google';

    return {
      'provider': provider.name,
      'ttsMode': ttsMode,
      'sttMode': sttMode,
      'googleVoiceAvailable': isGoogleVoiceServiceAvailable(),
      'geminiApiKey': dotenv.env['GEMINI_API_KEY']?.isNotEmpty ?? false,
      'googleApiKey': dotenv.env['GOOGLE_CLOUD_API_KEY']?.isNotEmpty ?? false,
    };
  }
}
