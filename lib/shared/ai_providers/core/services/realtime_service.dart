// ignore_for_file: prefer_final_parameters

import 'dart:typed_data';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/shared/ai_providers/core/registry/ai_provider_registry.dart';

/// Servicio unificado para OpenAI Realtime API (gpt-realtime)
///
/// Soporta las capacidades completas del nuevo modelo gpt-realtime:
/// - Audio de alta calidad con voces dinámicas del provider
/// - Comprensión inteligente con señales no verbales
/// - Function calling asíncrono avanzado
/// - Entrada de imágenes para conversación multimodal
/// - Instrucciones de voz específicas y adaptación de tono
/// - Cambio de idioma dinámico
///
/// Ejemplos de uso:
/// ```dart
/// // Cliente básico realtime (usa configuración del YAML)
/// final client = await RealtimeService.getConfiguredRealtimeClient();
///
/// // Con instrucciones de voz dinámicas
/// final client = await RealtimeService.getConfiguredRealtimeClient(
///   voiceInstructions: 'speak quickly and professionally',
/// );
///
/// // Con soporte de imágenes (TODO: Implementar para videollamadas)
/// final client = await RealtimeService.createMultimodalClient(
///   onImageRequest: (question) => handleImageQuestion(question)
/// );
///
/// // Con function calling avanzado (TODO: Implementar)
/// final client = await RealtimeService.createFunctionCallingClient(
///   tools: myTools,
///   onFunctionCall: (name, args) => handleFunction(name, args)
/// );
/// ```
class RealtimeService {
  /// Voces dinámicas obtenidas del provider configurado
  /// NOTA: Las voces deben venir del YAML, no hardcodeadas
  static Future<List<String>> getAvailableVoices() async {
    // TODO: Obtener dinámicamente del provider activo
    // final voices = await AIProviderConfigLoader.getVoicesForProvider('openai');
    // return voices;

    // Fallback temporal mientras se implementa la obtención dinámica
    return [];
  }

  /// Obtiene idiomas soportados dinámicamente de los providers disponibles
  static Future<List<String>> getSupportedLanguages() async {
    // For now, return common realtime languages
    // TODO: Integrate with provider-specific language capabilities
    return ['en', 'es', 'fr', 'de', 'it', 'pt', 'zh', 'ja', 'ko', 'ru', 'ar'];
  }

  /// Obtiene el cliente realtime configurado
  ///
  /// Usa el provider y configuración definidos en assets/ai_providers_config.yaml
  /// [voiceInstructions]: Instrucciones específicas de voz (opcional)
  /// [onText]: Callback para texto generado
  /// [onAudio]: Callback para audio generado (Uint8List para compatibilidad)
  /// [onCompleted]: Callback cuando termina la generación
  /// [onError]: Callback para errores
  /// [onUserTranscription]: Callback para transcripción del usuario
  /// [onFunctionCall]: Callback para function calling asíncrono
  /// [onImageRequest]: Callback para solicitudes de análisis de imagen
  /// [enableAsyncFunctions]: Habilitar function calling asíncrono (por defecto: true)
  /// [additionalParams]: Parámetros adicionales
  static Future<IRealtimeClient> getConfiguredRealtimeClient({
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

    // Obtener providers que soporten realtime conversation
    final realtimeProviders = registry
        .getAllProviders()
        .where((p) => p.supportsRealtime)
        .toList();

    if (realtimeProviders.isEmpty) {
      throw Exception(
        'No realtime providers available. '
        'Configure a provider with realtime support in assets/ai_providers_config.yaml.',
      );
    }

    // Usar el primer provider disponible (ordenados por prioridad en config)
    final provider = realtimeProviders.first;

    try {
      final client = await provider.createRealtimeClient();
      if (client != null) {
        // Configurar callbacks
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
    } catch (e) {
      throw Exception('Failed to create realtime client: $e');
    }

    throw Exception(
      'Failed to create realtime client. '
      'Check API keys and provider configuration.',
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

  /// Crea cliente multimodal con soporte de imágenes
  ///
  /// TODO: Implementar para videollamadas con IA enviando fotos
  /// Especializado para el análisis de imágenes con gpt-realtime
  /// El voice y provider se obtienen de la configuración
  static Future<IRealtimeClient> createMultimodalClient({
    String? voiceInstructions,
    Function(String)? onText,
    Function(Uint8List)? onAudio,
    Function()? onCompleted,
    Function(String)? onError,
    Function(String)? onUserTranscription,
    required Function(String imageDescription) onImageRequest,
    Map<String, dynamic>? additionalParams,
  }) async {
    return getConfiguredRealtimeClient(
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
  /// TODO: Implementar function calling asíncrono avanzado
  /// Optimizado para el function calling asíncrono de gpt-realtime
  /// El voice y provider se obtienen de la configuración
  static Future<IRealtimeClient> createFunctionCallingClient({
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
    return getConfiguredRealtimeClient(
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
