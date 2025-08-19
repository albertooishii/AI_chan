import 'package:ai_chan/chat/repositories/local_chat_repository.dart';
import 'package:ai_chan/chat/services/adapters/ai_chat_response_adapter.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/services/adapters/openai_adapter.dart';
import 'package:ai_chan/services/adapters/gemini_adapter.dart';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/services/adapters/openai_stt_adapter.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/services/adapters/default_tts_service.dart';
import 'package:ai_chan/services/adapters/google_stt_adapter.dart';
import 'package:ai_chan/services/adapters/google_tts_adapter.dart';
import 'dart:typed_data';

import 'package:ai_chan/services/openai_realtime_client.dart';
import 'package:ai_chan/services/gemini_realtime_client.dart';
import 'package:ai_chan/services/openai_service.dart';
import 'package:ai_chan/services/gemini_service.dart';
import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/services/adapters/profile_adapter.dart';
import 'package:ai_chan/core/config.dart';
// ...existing code...
import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;

/// Pequeñas fábricas/funciones de DI para la migración incremental.
/// Idealmente esto evolucionará a un contenedor/locator más completo.
IChatRepository getChatRepository() => LocalChatRepository();

IChatResponseService getChatResponseService() => const AiChatResponseAdapter();

/// Fábrica centralizada para obtener instancias de `IAIService` por modelo.
/// Mantiene singletons por proveedor para reutilizar estado interno (caches, preferencias de clave, etc.).
final Map<String, IAIService> _aiServiceSingletons = {};

IAIService getAIServiceForModel(String modelId) {
  final normalized = modelId.trim().toLowerCase();
  String key = normalized;
  if (key.isEmpty) key = 'default';
  if (_aiServiceSingletons.containsKey(key)) return _aiServiceSingletons[key]!;

  IAIService impl;
  if (normalized.startsWith('gpt-')) {
  // Create runtime OpenAIService and pass to adapter
  impl = OpenAIAdapter(runtime_factory.getRuntimeAIServiceForModel(normalized) as OpenAIService);
  } else if (normalized.startsWith('gemini-') || normalized.startsWith('imagen-')) {
  impl = GeminiAdapter(runtime_factory.getRuntimeAIServiceForModel(normalized) as GeminiService);
  } else if (normalized.isEmpty) {
    // Default behavior: prefer GeminiAdapter (google) for empty/unspecified
  impl = GeminiAdapter(runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash') as GeminiService);
  } else {
    // Fallback: prefer OpenAI for unknown ids
  impl = OpenAIAdapter(runtime_factory.getRuntimeAIServiceForModel('gpt-4o') as OpenAIService);
  }
  _aiServiceSingletons[key] = impl;
  return impl;
}

/// Fábrica para obtener las implementaciones runtime de `AIService` (OpenAIService/GeminiService)
// Use centralized runtime factory from `lib/core/runtime_factory.dart`

ISttService getSttService() => OpenAISttAdapter(runtime_factory.getRuntimeAIServiceForModel('gpt-4o') as OpenAIService);

ITtsService getTtsService() => const DefaultTtsService();

/// Provider-specific factories (useful for calls where we want Google-backed STT/TTS)
ISttService getSttServiceForProvider(String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') return const GoogleSttAdapter();
  return getSttService();
}

ITtsService getTtsServiceForProvider(String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') return const GoogleTtsAdapter();
  return getTtsService();
}

/// Fábrica que devuelve un cliente realtime compatible con la interfaz usada por VoiceCallController.
/// Para 'openai' devuelve el OpenAIRealtimeClient; para 'google' devuelve el GeminiCallOrchestrator (emulación).
dynamic getRealtimeClientForProvider(
  String provider, {
  String? model,
  void Function(String)? onText,
  void Function(Uint8List)? onAudio,
  void Function()? onCompleted,
  void Function(Object)? onError,
  void Function(String)? onUserTranscription,
}) {
  final p = provider.toLowerCase();
  if (p == 'openai') {
    return OpenAIRealtimeClient(
      model: model ?? 'gpt-4o-realtime-preview',
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
    );
  }
  // default to Gemini orchestrator for providers like 'google' that need emulation
  return GeminiCallOrchestrator(
    model: model ?? 'gemini-2.5-flash',
    onText: onText,
    onAudio: onAudio,
    onCompleted: onCompleted,
    onError: onError,
    onUserTranscription: onUserTranscription,
  );
}

IProfileService getProfileServiceForProvider([String? provider]) {
  // If caller passes provider explicitly, use it.
  if (provider != null && provider.trim().isNotEmpty) {
    final p = provider.toLowerCase();
  if (p == 'google' || p == 'gemini') return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash'));
  if (p == 'openai') return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel('gpt-4o'));
    return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash'));
  }

  // Otherwise, prefer the DEFAULT_TEXT_MODEL from config to infer the provider.
  final defaultTextModel = Config.getDefaultTextModel();
  final defaultImageModel = Config.getDefaultImageModel();
  String resolved = '';
  final modelToCheck = (defaultTextModel.isNotEmpty ? defaultTextModel : defaultImageModel).toLowerCase();
  if (modelToCheck.isNotEmpty) {
    if (modelToCheck.startsWith('gpt-')) resolved = 'openai';
    if (modelToCheck.startsWith('gemini-') || modelToCheck.startsWith('imagen-')) resolved = 'google';
  }

  // If we couldn't infer from DEFAULT_TEXT_MODEL/DEFAULT_IMAGE_MODEL, default to Gemini ('google').
  // This corresponds to using 'gemini-2.5-flash' as the default text model.
  if (resolved.isEmpty) resolved = 'google';

  if (resolved == 'google' || resolved == 'gemini') return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash'));
  if (resolved == 'openai') return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel('gpt-4o'));
  return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel('gemini-2.5-flash'));
}
