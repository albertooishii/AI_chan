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

/// Pequeñas fábricas/funciones de DI para la migración incremental.
/// Idealmente esto evolucionará a un contenedor/locator más completo.
IChatRepository getChatRepository() => LocalChatRepository();

IChatResponseService getChatResponseService() => const AiChatResponseAdapter();

IAIService getIAIServiceForModel(String modelId) {
  final normalized = modelId.trim().toLowerCase();
  if (normalized.startsWith('gpt-')) return OpenAIAdapter();
  if (normalized.startsWith('gemini-') || normalized.startsWith('imagen-')) return GeminiAdapter();
  // Default to OpenAIAdapter as fallback
  return OpenAIAdapter();
}

ISttService getSttService() => OpenAISttAdapter();

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
