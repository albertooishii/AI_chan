import 'package:flutter/foundation.dart';
import 'gemini_service.dart';
import 'openai_service.dart';
import '../models/ai_response.dart';

abstract class AIService {
  /// No se debe llamar directamente a este método, usa el método estático [sendMessage].
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    String systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
  });

  /// Punto único de entrada para enviar mensajes a la IA con fallback automático.
  static Future<AIResponse> sendMessage(
    List<Map<String, String>> history,
    String systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    String fallbackModel = 'gpt-4.1-mini',
  }) async {
    final m = model ?? 'gemini-2.5-flash';
    AIService? aiService = AIService.select(m);
    if (aiService == null) {
      throw Exception('No se pudo encontrar el servicio IA para el modelo: $m');
    }
    AIResponse response = await aiService.sendMessageImpl(
      history,
      systemPrompt,
      model: m,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );
    bool hasQuotaError(String text) {
      return text.contains('RESOURCE_EXHAUSTED') ||
          text.contains('quota') ||
          text.contains('429') ||
          text.contains('You exceeded your current quota') ||
          text.contains('Error: Falta la API key');
    }

    if (hasQuotaError(response.text) && m != fallbackModel) {
      debugPrint(
        '[AIService.sendMessage] Modelo $m falló por cuota, reintentando con $fallbackModel...',
      );
      aiService = AIService.select(fallbackModel);
      if (aiService == null) {
        throw Exception(
          'No se pudo encontrar el servicio IA para el modelo: $fallbackModel',
        );
      }
      response = await aiService.sendMessageImpl(
        history,
        systemPrompt,
        model: fallbackModel,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );
    }
    return response;
  }

  Future<List<String>> getAvailableModels();

  /// Selecciona el servicio IA adecuado según el modelo
  static AIService? select(String modelId) {
    // Log para depuración
    debugPrint('[AIService.select] Modelo recibido: "$modelId"');
    if (modelId.trim().isEmpty) {
      throw Exception('AIService.select: El modelo recibido está vacío.');
    }
    final normalized = modelId.trim().toLowerCase();
    if (normalized.startsWith('gpt-')) return OpenAIService();
    if (normalized.startsWith('gemini-')) return GeminiService();
    if (normalized.startsWith('imagen-')) return GeminiService();
    throw Exception('AIService.select: Modelo "$modelId" no reconocido.');
  }
}

/// Devuelve la lista combinada de modelos de todos los servicios IA
Future<List<String>> getAllAIModels() async {
  final services = [GeminiService(), OpenAIService()];
  final allModels = <String>[];
  for (final service in services) {
    try {
      final models = await service.getAvailableModels();
      allModels.addAll(models);
    } catch (_) {
      // Si falla un servicio, ignora y sigue
    }
  }
  return allModels;
}
