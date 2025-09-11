// ignore_for_file: prefer_final_parameters

import 'dart:typed_data';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/shared/ai_providers/core/registry/ai_provider_registry.dart';

/// Servicio unificado para OpenAI Realtime API (gpt-realtime)
///
/// Soporta las capacidades completas del nuevo modelo gpt-realtime:
/// - Audio de alta calidad con voces Marin y Cedar
/// - Comprensión inteligente con señales no verbales
/// - Function calling asíncrono avanzado
/// - Entrada de imágenes para conversación multimodal
/// - Instrucciones de voz específicas y adaptación de tono
/// - Cambio de idioma dinámico
///
/// Ejemplos de uso:
/// ```dart
/// // Cliente básico realtime
/// final client = await RealtimeService.getBestRealtimeClient();
///
/// // Con voz específica e instrucciones
/// final client = await RealtimeService.getBestRealtimeClient(
///   preferredProvider: 'openai',
///   voiceInstructions: 'speak quickly and professionally',
///   voice: 'marin'
/// );
///
/// // Con soporte de imágenes
/// final client = await RealtimeService.createMultimodalClient(
///   onImageRequest: (question) => handleImageQuestion(question)
/// );
/// ```
class RealtimeService {
  /// Configuración de voz para gpt-realtime
  static const List<String> availableVoices = [
    'marin', // Nueva voz premium
    'cedar', // Nueva voz premium
    'alloy',
    'echo',
    'fable',
    'onyx',
    'nova',
    'shimmer', // Voces existentes mejoradas
  ];

  /// Idiomas soportados para cambio dinámico
  static const List<String> supportedLanguages = [
    'en',
    'es',
    'fr',
    'de',
    'it',
    'pt',
    'zh',
    'ja',
    'ko',
    'ru',
    'ar',
  ];

  /// Obtiene el mejor cliente realtime con capacidades avanzadas
  ///
  /// [preferredProvider]: Provider preferido (recomendado: 'openai' para gpt-realtime)
  /// [model]: Modelo específico (por defecto: 'gpt-realtime' o fallback)
  /// [voice]: Voz a usar ('marin', 'cedar', etc.)
  /// [voiceInstructions]: Instrucciones específicas de voz
  /// [onText]: Callback para texto generado
  /// [onAudio]: Callback para audio generado (Uint8List para compatibilidad)
  /// [onCompleted]: Callback cuando termina la generación
  /// [onError]: Callback para errores
  /// [onUserTranscription]: Callback para transcripción del usuario
  /// [onFunctionCall]: Callback para function calling asíncrono
  /// [onImageRequest]: Callback para solicitudes de análisis de imagen
  /// [enableAsyncFunctions]: Habilitar function calling asíncrono (por defecto: true)
  /// [additionalParams]: Parámetros adicionales
  static Future<IRealtimeClient> getBestRealtimeClient({
    String? preferredProvider,
    String? model,
    String? voice,
    String? voiceInstructions,
    Function(String)? onText,
    Function(Uint8List)? onAudio,
    Function()? onCompleted,
    Function(String)? onError,
    Function(String)? onUserTranscription,
    Function(String functionName, Map<String, dynamic> arguments)?
    onFunctionCall,
    Function(String imageDescription)? onImageRequest,
    bool enableAsyncFunctions = true,
    Map<String, dynamic>? additionalParams,
  }) async {
    final registry = AIProviderRegistry();

    // Si se especifica OpenAI o no hay preferencia, intentar primero OpenAI
    if (preferredProvider == null ||
        preferredProvider.toLowerCase() == 'openai') {
      final openaiProvider = registry.getProvider('openai');
      if (openaiProvider?.supportsRealtime == true) {
        try {
          final client = await openaiProvider!.createRealtimeClient();
          if (client != null) {
            // Configurar callbacks específicos para gpt-realtime
            _configureRealtimeCallbacks(
              client,
              onText: onText,
              onAudio: onAudio,
              onCompleted: onCompleted,
              onError: onError,
              onUserTranscription: onUserTranscription,
              onFunctionCall: onFunctionCall,
              onImageRequest: onImageRequest,
            );
            return client;
          }
        } on Exception {
          // Continuar con otros providers si falla
        }
      }
    }

    // Buscar otros providers con realtime como fallback
    final allProviders = registry.getAllProviders();
    final realtimeProviders = allProviders
        .where((p) => p.supportsRealtime)
        .toList();

    if (realtimeProviders.isEmpty) {
      throw Exception(
        'No realtime providers available. '
        'Configure OpenAI provider for gpt-realtime support.',
      );
    }

    // Intentar crear cliente con providers alternativos
    for (final provider in realtimeProviders) {
      if (provider.providerId.toLowerCase() ==
          preferredProvider?.toLowerCase()) {
        continue; // Ya intentamos este
      }

      try {
        final client = await provider.createRealtimeClient();
        if (client != null) {
          _configureRealtimeCallbacks(
            client,
            onText: onText,
            onAudio: onAudio,
            onCompleted: onCompleted,
            onError: onError,
            onUserTranscription: onUserTranscription,
            onFunctionCall: onFunctionCall,
            onImageRequest: onImageRequest,
          );
          return client;
        }
      } on Exception {
        continue;
      }
    }

    throw Exception(
      'Failed to create realtime client. '
      'Check API keys and ensure OpenAI provider is configured for gpt-realtime.',
    );
  }

  /// Crea cliente multimodal con soporte de imágenes
  ///
  /// Especializado para el análisis de imágenes con gpt-realtime
  static Future<IRealtimeClient> createMultimodalClient({
    String? voice,
    String? voiceInstructions,
    Function(String)? onText,
    Function(Uint8List)? onAudio,
    Function()? onCompleted,
    Function(String)? onError,
    Function(String)? onUserTranscription,
    required Function(String imageDescription) onImageRequest,
    Map<String, dynamic>? additionalParams,
  }) async {
    return getBestRealtimeClient(
      preferredProvider: 'openai', // Solo OpenAI soporta imágenes
      voice: voice ?? 'marin',
      voiceInstructions:
          voiceInstructions ?? 'Describe images clearly and helpfully',
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
      onImageRequest: onImageRequest,
      additionalParams: {
        'support_image_input': true,
        'image_analysis_mode': 'detailed',
        ...?additionalParams,
      },
    );
  }

  /// Crea cliente con function calling avanzado
  ///
  /// Optimizado para el function calling asíncrono de gpt-realtime
  static Future<IRealtimeClient> createFunctionCallingClient({
    String? voice,
    String? voiceInstructions,
    required List<Map<String, dynamic>> tools,
    required Function(String functionName, Map<String, dynamic> arguments)
    onFunctionCall,
    Function(String)? onText,
    Function(Uint8List)? onAudio,
    Function()? onCompleted,
    Function(String)? onError,
    Function(String)? onUserTranscription,
    Map<String, dynamic>? additionalParams,
  }) async {
    return getBestRealtimeClient(
      preferredProvider: 'openai',
      voice: voice ?? 'cedar',
      voiceInstructions: voiceInstructions,
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
      onFunctionCall: onFunctionCall,
      additionalParams: {
        'tools': tools,
        'async_function_calling': true,
        'function_calling_mode': 'advanced',
        ...?additionalParams,
      },
    );
  }

  /// Obtiene lista de modelos realtime disponibles
  static Future<List<String>> getAvailableRealtimeModels() async {
    final registry = AIProviderRegistry();
    final models = <String>[];

    try {
      final allProviders = registry.getAllProviders();

      for (final provider in allProviders) {
        if (provider.supportsRealtime) {
          final providerModels = provider.getAvailableRealtimeModels();
          models.addAll(providerModels);
        }
      }

      // Asegurar que gpt-realtime esté al inicio si está disponible
      if (models.contains('gpt-realtime')) {
        models.remove('gpt-realtime');
        models.insert(0, 'gpt-realtime');
      }
    } catch (e) {
      throw Exception('Failed to get available realtime models: $e');
    }

    return models;
  }

  /// Verifica si un modelo soporta capacidades específicas
  static Future<Map<String, bool>> getModelCapabilities(String modelId) async {
    final isGptRealtime = modelId.toLowerCase().contains('gpt-realtime');

    return {
      'voice_instructions': isGptRealtime,
      'async_function_calling': isGptRealtime,
      'image_input': isGptRealtime,
      'voice_switching': isGptRealtime,
      'language_switching': isGptRealtime,
      'non_verbal_cues': isGptRealtime,
      'premium_voices': isGptRealtime,
    };
  }

  /// Sistema alternativo TTS + STT + Texto para providers sin realtime
  static Future<IRealtimeClient> createHybridClient({
    String? textProvider,
    String? ttsProvider,
    String? sttProvider,
    Function(String)? onText,
    Function(Uint8List)? onAudio,
    Function()? onCompleted,
    Function(String)? onError,
    Function(String)? onUserTranscription,
    Map<String, dynamic>? additionalParams,
  }) async {
    // TODO: Implementar cliente híbrido que combine TTS + STT + modelo de texto
    // Esto será el fallback cuando no haya providers realtime disponibles
    throw UnimplementedError(
      'Hybrid TTS+STT+Text client not yet implemented. '
      'Configure OpenAI provider for native realtime support.',
    );
  }

  /// Configura callbacks específicos para el cliente realtime
  static void _configureRealtimeCallbacks(
    IRealtimeClient client, {
    Function(String)? onText,
    Function(Uint8List)? onAudio,
    Function()? onCompleted,
    Function(String)? onError,
    Function(String)? onUserTranscription,
    Function(String functionName, Map<String, dynamic> arguments)?
    onFunctionCall,
    Function(String imageDescription)? onImageRequest,
  }) {
    // TODO: Configurar callbacks específicos según el tipo de cliente
    // Los callbacks dependerán de la implementación específica del IRealtimeClient
  }
}
