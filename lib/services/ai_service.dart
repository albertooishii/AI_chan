import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/debug_call_logger/debug_call_logger.dart';
import 'package:flutter/foundation.dart';
import 'gemini_service.dart';
import 'openai_service.dart';
import '../models/ai_response.dart';
import '../models/system_prompt.dart';

abstract class AIService {
  /// Implementación base para enviar mensajes a la IA.
  ///
  /// Si se adjunta imagen, debe combinarse en el mismo bloque/parte que el texto del último mensaje 'user',
  /// siguiendo el patrón multimodal de OpenAI y Gemini (texto + imagen juntos, no por separado).
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  });

  /// Punto único de entrada para enviar mensajes a la IA con fallback automático.
  static Future<AIResponse> sendMessage(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    model = model ?? dotenv.env['DEFAULT_TEXT_MODEL'] ?? '';
    String fallbackModel = 'gpt-4.1-mini';

    AIService? aiService = AIService.select(model);
    if (aiService == null) {
      debugPrint('[AIService.sendMessage] No se pudo encontrar el servicio IA para el modelo: $model');
      return AIResponse(text: '');
    }

    // Guardar logs usando debugLogCallPrompt (solo en debug/profile y escritorio)
    await debugLogCallPrompt('ai_service_send', {
      'history': history,
      'systemPrompt': systemPrompt.toJson(),
      'model': model,
      if (imageBase64 != null) 'imageBase64': imageBase64,
      if (imageMimeType != null) 'imageMimeType': imageMimeType,
    });
    // Revertir sanitización del history
    final bool requestHadImage = imageBase64 != null && imageBase64.isNotEmpty;

    AIResponse response = await aiService.sendMessageImpl(
      history,
      systemPrompt,
      model: model,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );
    // Eliminar siempre etiquetas [img_caption] del texto de la respuesta.
    // Solo cuando la petición ORIGINAL incluía imagen (requestHadImage) se guardará
    // el prompt extraído; si no, no se guarda nada sobre la imagen (solo se limpia el texto).
    if (response.text.trim().isNotEmpty) {
      try {
        final tagRegex = RegExp(r'\[img_caption\](.*?)\[/img_caption\]', caseSensitive: false, dotAll: true);
        final match = tagRegex.firstMatch(response.text);
        final cleanedText = response.text.replaceAll(tagRegex, '').trim();
        // Además: si el servicio devolvió un `revised_prompt` dentro del texto y
        // `response.prompt` está vacío, extraerlo y usarlo como prompt.
        String finalPrompt = response.prompt.trim();
        // Si el servicio no rellenó 'prompt', intentar extraer 'revised_prompt' de response.text
        if (finalPrompt.isEmpty) {
          try {
            final patterns = [
              RegExp(r'"revised_prompt"\s*:\s*"([^"]+)"', caseSensitive: false),
              RegExp(r"'revised_prompt'\s*:\s*'([^']+)'", caseSensitive: false),
              RegExp(r'\brevised_prompt\b\s*[:=]\s*"([^"]+)"', caseSensitive: false),
              RegExp(r'\brevisedPrompt\b\s*[:=]\s*"([^"]+)"', caseSensitive: false),
              RegExp(r'\brevised_prompt\b\s*[:=]\s*([^\n\r]+)', caseSensitive: false),
            ];
            for (final p in patterns) {
              final m = p.firstMatch(response.text);
              if (m != null && m.groupCount >= 1) {
                finalPrompt = m.group(1)!.trim();
                if (finalPrompt.isNotEmpty) break;
              }
            }
          } catch (_) {}
        }
        // Determinar si la respuesta incluye una imagen (generada por la IA)
        final bool responseHasImage = response.base64.trim().isNotEmpty || response.seed.trim().isNotEmpty;
        if (match != null && match.groupCount >= 1) {
          final raw = match.group(1);
          if (raw != null && raw.trim().isNotEmpty) {
            final extracted = raw.trim();
            // Guardar el prompt extraído si la petición original incluía imagen
            // o si la respuesta contiene una imagen generada por la IA (revised_prompt viene del servicio)
            if (requestHadImage || responseHasImage) {
              finalPrompt = finalPrompt.isEmpty ? extracted : finalPrompt;
            } else {
              // No guardar prompts si ni la petición ni la respuesta contienen imagen
              finalPrompt = '';
            }
          }
        } else {
          // No hay match; si ni la petición original ni la respuesta tienen imagen, borrar prompt por seguridad
          if (!requestHadImage && !responseHasImage) finalPrompt = '';
        }
        response = AIResponse(text: cleanedText, base64: response.base64, seed: response.seed, prompt: finalPrompt);
      } catch (_) {}
    }
    // Guardar la respuesta usando debugLogCallPrompt
    await debugLogCallPrompt('ai_service_response', {
      'response': response.toJson(),
      'model': model,
      'timestamp': DateTime.now().toIso8601String(),
    });
    bool hasQuotaError(String text) {
      return text.contains('RESOURCE_EXHAUSTED') ||
          text.contains('quota') ||
          text.contains('429') ||
          text.contains('You exceeded your current quota') ||
          text.contains('Error: Falta la API key');
    }

    if (hasQuotaError(response.text) && model != fallbackModel) {
      debugPrint('[AIService.sendMessage] Modelo $model falló por cuota, reintentando con $fallbackModel...');
      aiService = AIService.select(fallbackModel);
      if (aiService == null) {
        debugPrint('[AIService.sendMessage] No se pudo encontrar el servicio IA para el modelo: $fallbackModel');
        return AIResponse(text: '');
      }
      response = await aiService.sendMessageImpl(
        history,
        systemPrompt,
        model: fallbackModel,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
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
      debugPrint('[AIService.select] El modelo recibido está vacío.');
      return null;
    }
    final normalized = modelId.trim().toLowerCase();
    if (normalized.startsWith('gpt-')) return OpenAIService();
    if (normalized.startsWith('gemini-')) return GeminiService();
    if (normalized.startsWith('imagen-')) return GeminiService();
    debugPrint('[AIService.select] Modelo "$modelId" no reconocido.');
    return null;
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
