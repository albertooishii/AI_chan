// dotenv no se usa aquí; la configuración se centraliza en runtime_factory / Config
import '../utils/debug_call_logger/debug_call_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/services/ai_runtime_provider.dart' as runtime_factory;
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/cache/cache_service.dart';

abstract class AIService {
  /// Test hook: permite inyectar una implementación fake durante tests.
  static AIService? testOverride;

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
    model = model ?? runtime_factory.getDefaultModelId();
    // Resolver runtime: prefer testOverride si está presente, si no usar la fábrica
    AIService? override = AIService.testOverride;
    late AIService aiService;
    if (override != null) {
      aiService = override;
    } else {
      try {
        aiService = runtime_factory.getRuntimeAIServiceForModel(model);
      } catch (e) {
        // Fall back silently: return an empty response on resolution failure.
        return AIResponse(text: '');
      }
    }

    // Sanity: asegurar que el runtime seleccionado coincide con el prefijo del modelo
    try {
      final modelNorm = model.trim().toLowerCase();
      final implType = aiService.runtimeType.toString();
      // IMPORTANT: If a test override is set, do not replace it. Tests rely on testOverride fakes.
      if (AIService.testOverride == null) {
        if (modelNorm.startsWith('gpt-') && implType != 'OpenAIService') {
          debugPrint('[AIService] Runtime mismatch: recreating OpenAIService for $modelNorm');
          aiService = runtime_factory.getRuntimeAIServiceForModel(modelNorm);
        } else if ((modelNorm.startsWith('gemini-') || modelNorm.startsWith('imagen-')) &&
            implType != 'GeminiService') {
          debugPrint('[AIService] Runtime mismatch: recreating GeminiService for $modelNorm');
          aiService = runtime_factory.getRuntimeAIServiceForModel(modelNorm);
        }
      } else {
        // keep test override silently
      }
    } catch (_) {}

    // Guardar logs usando debugLogCallPrompt (solo en debug/profile y escritorio).
    // Registramos una versión truncada/segura de lo que enviamos: previews del history
    // y del systemPrompt para evitar volcar imágenes completas en disco.
    try {
      final runtimeTypeStr = aiService.runtimeType.toString();
      // Store full history and systemPrompt, but truncate only base64 content.
      final sysJson = systemPrompt.toJson();
      await debugLogCallPrompt('ai_service_send', {
        'runtime': runtimeTypeStr,
        'model': model,
        'history': history,
        'systemPrompt': sysJson,
        if (imageBase64 != null) 'image_base64_length': imageBase64.length,
        if (imageBase64 != null)
          'image_base64_preview': imageBase64.length > 400 ? '${imageBase64.substring(0, 400)}...' : imageBase64,
        if (imageMimeType != null) 'image_mime_type': imageMimeType,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    // Revertir sanitización del history
    final bool requestHadImage = imageBase64 != null && imageBase64.isNotEmpty;

    final int startMs = DateTime.now().millisecondsSinceEpoch;
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
    // Guardar la respuesta usando debugLogCallPrompt con un preview seguro.
    try {
      final runtimeTypeStr = aiService.runtimeType.toString();
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      await debugLogCallPrompt('ai_service_response', {
        'runtime': runtimeTypeStr,
        'model': model,
        'duration_ms': durationMs,
        // Keep full text/prompt/seed but truncate only base64.
        'response_text': response.text,
        'response_prompt': response.prompt,
        'response_seed': response.seed,
        'response_base64_length': response.base64.length,
        'response_base64_preview': response.base64.length > 400
            ? '${response.base64.substring(0, 400)}...'
            : response.base64,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    // Nota: no se reintenta con modelos de fallback automáticamente: la resolución de runtimes
    // debe ser explícita vía DI/fábrica. Si hay un error por cuota, devolvemos la respuesta tal cual
    // y es responsabilidad del caller o la capa superior decidir reintentar con otro modelo.
    return response;
  }

  Future<List<String>> getAvailableModels();

  /// Selecciona el servicio IA adecuado según el modelo
  // Note: AIService.select removed — runtime resolution must use runtime_factory.getRuntimeAIServiceForModel
}

/// Devuelve la lista combinada de modelos de todos los servicios IA
Future<List<String>> getAllAIModels({bool forceRefresh = false}) async {
  // Pedimos instancias a la fábrica centralizada para evitar instanciaciones dispersas
  final services = [
    runtime_factory.getRuntimeAIServiceForModel(Config.requireDefaultImageModel()),
    runtime_factory.getRuntimeAIServiceForModel(Config.requireDefaultTextModel()),
  ];

  final allModels = <String>[];

  // Attempt to read per-service cache first (unless forceRefresh)
  if (!forceRefresh) {
    try {
      for (final service in services) {
        final providerName = service.runtimeType.toString().toLowerCase();
        final cached = await CacheService.getCachedModels(provider: providerName);
        if (cached != null && cached.isNotEmpty) {
          allModels.addAll(cached);
        }
      }
      if (allModels.isNotEmpty) {
        return allModels;
      }
    } catch (_) {
      // ignore cache errors and proceed to fetch
    }
  }

  // If we reach here, fetch from services and save to cache
  for (final service in services) {
    try {
      final models = await service.getAvailableModels();
      if (models.isNotEmpty) {
        allModels.addAll(models);
        // Save per-service cache
        try {
          final providerName = service.runtimeType.toString().toLowerCase();
          await CacheService.saveModelsToCache(models: models, provider: providerName);
        } catch (_) {}
      }
    } catch (_) {
      // Si falla un servicio, ignora y sigue
    }
  }

  return allModels;
}
