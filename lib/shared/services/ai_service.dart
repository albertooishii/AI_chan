// dotenv no se usa aquí; la configuración se centraliza en runtime_factory / Config
import '../utils/debug_call_logger/debug_call_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/services/ai_runtime_provider.dart'
    as runtime_factory;
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/model_utils.dart';
import 'package:ai_chan/core/cache/cache_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

abstract class AIService {
  /// Test hook: permite inyectar una implementación fake durante tests.
  static AIService? testOverride;

  /// Implementación base para enviar mensajes a la IA.
  ///
  /// Si se adjunta imagen, debe combinarse en el mismo bloque/parte que el texto del último mensaje 'user',
  /// siguiendo el patrón multimodal de OpenAI y Gemini (texto + imagen juntos, no por separado).
  Future<AIResponse> sendMessageImpl(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  });

  /// Maneja reintentos con backoff exponencial para errores transitorios (503, 429, etc.)
  /// Este método es usado internamente por AIService.sendMessage
  static Future<AIResponse> _retryOnTransientErrors(
    final Future<AIResponse> Function() operation,
    final String modelName,
    final String serviceName,
  ) async {
    const maxRetries = 3;
    const baseDelayMs = 1000; // 1 segundo base

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await operation();

        // Si la respuesta contiene texto, consideramos que fue exitosa
        if (response.text.isNotEmpty) {
          return response;
        }

        // Si está vacía, podría ser un error que no lanzó excepción
        // Intentamos detectar si es un error transitorio por el contenido
        if (attempt < maxRetries && _isTransientError(response.text)) {
          final delayMs = baseDelayMs * (1 << attempt);
          Log.w(
            '[$serviceName] Posible error transitorio detectado para modelo $modelName (intento ${attempt + 1}/$maxRetries). Reintentando en ${delayMs}ms...',
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        return response;
      } on Exception catch (e) {
        // Verificar si es un error transitorio que merece reintento
        if (attempt < maxRetries && _isTransientException(e)) {
          final delayMs = baseDelayMs * (1 << attempt);
          Log.w(
            '[$serviceName] Error transitorio para modelo $modelName (intento ${attempt + 1}/$maxRetries): $e. Reintentando en ${delayMs}ms...',
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        // Si no es transitorio o agotamos reintentos, relanzar la excepción
        rethrow;
      }
    }

    // Esto no debería ejecutarse, pero por seguridad
    return AIResponse(text: 'Error: se agotaron los reintentos');
  }

  /// Detecta si una excepción representa un error transitorio que merece reintento
  static bool _isTransientException(final Exception e) {
    final errorStr = e.toString().toLowerCase();

    // Errores de conexión de red
    if (errorStr.contains('socketexception') ||
        errorStr.contains('timeoutexception') ||
        errorStr.contains('connection') ||
        errorStr.contains('network')) {
      return true;
    }

    // Errores HTTP específicos (503, 429, 502, 504)
    if (errorStr.contains('503') ||
        errorStr.contains('429') ||
        errorStr.contains('502') ||
        errorStr.contains('504')) {
      return true;
    }

    // Errores específicos de servicios de IA
    if (errorStr.contains('overloaded') ||
        errorStr.contains('rate limit') ||
        errorStr.contains('quota') ||
        errorStr.contains('temporarily unavailable') ||
        errorStr.contains('service unavailable')) {
      return true;
    }

    return false;
  }

  /// Detecta si el contenido de respuesta indica un error transitorio
  static bool _isTransientError(final String responseText) {
    final text = responseText.toLowerCase();

    return text.contains('overloaded') ||
        text.contains('rate limit') ||
        text.contains('quota') ||
        text.contains('temporarily unavailable') ||
        text.contains('service unavailable') ||
        text.contains('error 503') ||
        text.contains('error 429') ||
        text.contains('error 502') ||
        text.contains('error 504');
  }

  /// Punto único de entrada para enviar mensajes a la IA con fallback automático.
  static Future<AIResponse> sendMessage(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    model = model ?? runtime_factory.getDefaultModelId();
    // Resolver runtime: prefer testOverride si está presente, si no usar la fábrica
    final AIService? override = AIService.testOverride;
    late AIService aiService;
    if (override != null) {
      aiService = override;
    } else {
      try {
        aiService = runtime_factory.getRuntimeAIServiceForModel(model);
      } on Exception {
        // Fall back silently: return an empty response on resolution failure.
        return AIResponse(text: '');
      }
    }

    // Log which model and runtime implementation we're using (helpful for debugging)
    try {
      debugPrint(
        '[AIService] sendMessage -> model="$model", runtime="${aiService.runtimeType}"',
      );
    } on Exception catch (_) {}

    // Sanity: asegurar que el runtime seleccionado coincide con el prefijo del modelo
    try {
      final modelNorm = model.trim().toLowerCase();
      final implType = aiService.runtimeType.toString();
      // IMPORTANT: If a test override is set, do not replace it. Tests rely on testOverride fakes.
      if (AIService.testOverride == null) {
        if (modelNorm.startsWith('gpt-') && implType != 'OpenAIService') {
          debugPrint(
            '[AIService] Runtime mismatch: recreating OpenAIService for $modelNorm',
          );
          aiService = runtime_factory.getRuntimeAIServiceForModel(modelNorm);
        } else if ((modelNorm.startsWith('gemini-') ||
                modelNorm.startsWith('imagen-')) &&
            implType != 'GeminiService') {
          debugPrint(
            '[AIService] Runtime mismatch: recreating GeminiService for $modelNorm',
          );
          aiService = runtime_factory.getRuntimeAIServiceForModel(modelNorm);
        }
      } else {
        // keep test override silently
      }
    } on Exception catch (_) {}

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
          'image_base64_preview': imageBase64.length > 400
              ? '${imageBase64.substring(0, 400)}...'
              : imageBase64,
        if (imageMimeType != null) 'image_mime_type': imageMimeType,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } on Exception catch (_) {}
    // Revertir sanitización del history
    final bool requestHadImage = imageBase64 != null && imageBase64.isNotEmpty;

    final int startMs = DateTime.now().millisecondsSinceEpoch;

    // Usar reintentos automáticos para errores transitorios
    AIResponse response = await _retryOnTransientErrors(
      () => aiService.sendMessageImpl(
        history,
        systemPrompt,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      ),
      model,
      aiService.runtimeType.toString(),
    );
    // Eliminar siempre etiquetas [img_caption] del texto de la respuesta.
    // Solo cuando la petición ORIGINAL incluía imagen (requestHadImage) se guardará
    // el prompt extraído; si no, no se guarda nada sobre la imagen (solo se limpia el texto).
    if (response.text.trim().isNotEmpty) {
      try {
        final tagRegex = RegExp(
          r'\[img_caption\](.*?)\[/img_caption\]',
          caseSensitive: false,
          dotAll: true,
        );
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
              RegExp(
                r'\brevised_prompt\b\s*[:=]\s*"([^"]+)"',
                caseSensitive: false,
              ),
              RegExp(
                r'\brevisedPrompt\b\s*[:=]\s*"([^"]+)"',
                caseSensitive: false,
              ),
              RegExp(
                r'\brevised_prompt\b\s*[:=]\s*([^\n\r]+)',
                caseSensitive: false,
              ),
            ];
            for (final p in patterns) {
              final m = p.firstMatch(response.text);
              if (m != null && m.groupCount >= 1) {
                finalPrompt = m.group(1)!.trim();
                if (finalPrompt.isNotEmpty) break;
              }
            }
          } on Exception catch (_) {}
        }
        // Determinar si la respuesta incluye una imagen (generada por la IA)
        final bool responseHasImage =
            response.base64.trim().isNotEmpty ||
            response.seed.trim().isNotEmpty;
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
        response = AIResponse(
          text: cleanedText,
          base64: response.base64,
          seed: response.seed,
          prompt: finalPrompt,
        );
      } on Exception catch (_) {}
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
    } on Exception catch (_) {}

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
Future<List<String>> getAllAIModels({final bool forceRefresh = false}) async {
  // Query providers in preferred UI order and append each provider's list
  // exactly as the provider returns it. This preserves provider-specific
  // ordering (for example OpenAI/Gemini providers already sort by recency).
  final providerOrder = ModelUtils.preferredOrder();
  final allModels = <String>[];

  String representativeForProvider(final String provider) {
    switch (provider) {
      case 'Google':
        return Config.getDefaultTextModel().startsWith('gemini-')
            ? Config.getDefaultTextModel()
            : 'gemini-2.5-pro';
      case 'Grok':
        return 'grok-3';
      case 'OpenAI':
        return 'gpt-4';
      default:
        return Config.getDefaultTextModel();
    }
  }

  // Función para determinar si la caché parece incompleta para un proveedor
  bool isCacheIncomplete(
    final String provider,
    final List<String> cachedModels,
  ) {
    switch (provider) {
      case 'grokservice':
        // Si hay API key de Grok configurada pero la caché tiene pocos modelos (< 5),
        // consideramos que está incompleta
        final hasGrokKey = Config.getGrokKey().trim().isNotEmpty;
        return hasGrokKey && cachedModels.length < 5;
      case 'openaiservice':
        // Similar para OpenAI
        final hasOpenAIKey = Config.getOpenAIKey().trim().isNotEmpty;
        return hasOpenAIKey && cachedModels.length < 5;
      case 'geminiservice':
        // Para Gemini, esperamos al menos algunos modelos
        return cachedModels.length < 3;
      default:
        return false;
    }
  }

  for (final provider in providerOrder) {
    try {
      final rep = representativeForProvider(provider);
      final service = runtime_factory.getRuntimeAIServiceForModel(rep);
      final providerName = service.runtimeType.toString().toLowerCase();

      // If cache present and allowed, use it as-is (preserves order)
      bool shouldUseCache = !forceRefresh;
      if (shouldUseCache) {
        try {
          final cached = await CacheService.getCachedModels(
            provider: providerName,
          );
          if (cached != null && cached.isNotEmpty) {
            // Verificar si la caché parece incompleta
            if (isCacheIncomplete(providerName, cached)) {
              // Forzar refresh porque la caché parece incompleta
              shouldUseCache = false;
            } else {
              allModels.addAll(cached);
              continue;
            }
          }
        } on Exception catch (_) {}
      }

      // Fetch live and append exactly as returned (si no usamos caché o está incompleta)
      if (!shouldUseCache) {
        try {
          final models = await service.getAvailableModels();
          if (models.isNotEmpty) {
            allModels.addAll(models);
            try {
              await CacheService.saveModelsToCache(
                models: models,
                provider: providerName,
              );
            } on Exception catch (_) {}
          }
        } on Exception catch (_) {}
      }
    } on Exception catch (_) {}
  }

  // Probe defaults for any runtimes not covered above
  final extras = {
    Config.requireDefaultImageModel(),
    Config.requireDefaultTextModel(),
  };
  for (final ex in extras) {
    final n = ex.trim().toLowerCase();
    if (n.startsWith('gpt-') && providerOrder.contains('OpenAI')) continue;
    if ((n.startsWith('gemini-') || n.startsWith('imagen-')) &&
        providerOrder.contains('Google')) {
      continue;
    }
    if (n.startsWith('grok-') && providerOrder.contains('Grok')) continue;
    try {
      final s = runtime_factory.getRuntimeAIServiceForModel(ex);
      final providerName = s.runtimeType.toString().toLowerCase();
      bool shouldUseCache = !forceRefresh;
      if (shouldUseCache) {
        try {
          final cached = await CacheService.getCachedModels(
            provider: providerName,
          );
          if (cached != null && cached.isNotEmpty) {
            // Verificar si la caché parece incompleta
            if (isCacheIncomplete(providerName, cached)) {
              shouldUseCache = false;
            } else {
              allModels.addAll(cached);
              continue;
            }
          }
        } on Exception catch (_) {}
      }
      if (!shouldUseCache) {
        final models = await s.getAvailableModels();
        if (models.isNotEmpty) {
          allModels.addAll(models);
          try {
            await CacheService.saveModelsToCache(
              models: models,
              provider: providerName,
            );
          } on Exception catch (_) {}
        }
      }
    } on Exception catch (_) {}
  }

  return allModels;
}
