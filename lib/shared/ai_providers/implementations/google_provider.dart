import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_metadata.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/http_connector.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/chat/infrastructure/adapters/prompt_builder_service.dart'
    as pb;
import 'dart:convert';
import 'dart:async';

/// Google Gemini provider implementation using the new architecture.
/// This provider directly implements HTTP calls to Google AI API without depending on GeminiService.
class GoogleProvider implements IAIProvider {
  GoogleProvider() {
    _metadata = const AIProviderMetadata(
      providerId: 'google',
      providerName: 'Google Gemini',
      company: 'Google',
      version: '1.0.0',
      description:
          'Google Gemini models with vision, image generation, and realtime capabilities',
      supportedCapabilities: [
        AICapability.textGeneration,
        AICapability.imageGeneration,
        AICapability.imageAnalysis,
        AICapability.realtimeConversation,
      ],
      defaultModels: {
        AICapability.textGeneration: 'gemini-2.5-flash',
        AICapability.imageGeneration: 'gemini-2.5-flash-image-preview',
        AICapability.imageAnalysis: 'gemini-2.5-flash',
        AICapability.realtimeConversation: 'gemini-2.5-flash',
      },
      availableModels: {
        AICapability.textGeneration: [
          'gemini-2.5-flash',
          'gemini-2.5',
          'gemini-1.5-flash-latest',
        ],
        AICapability.imageGeneration: ['gemini-2.5-flash-image-preview'],
        AICapability.imageAnalysis: ['gemini-2.5-flash', 'gemini-2.5'],
        AICapability.realtimeConversation: ['gemini-2.5-flash'],
      },
      rateLimits: {'requests_per_minute': 2000, 'tokens_per_minute': 1000000},
      requiresAuthentication: true,
      requiredConfigKeys: ['GEMINI_API_KEY'],
      maxContextTokens: 1000000,
      maxOutputTokens: 8192,
      supportsStreaming: true,
      supportsFunctionCalling: true,
    );
  }
  late final AIProviderMetadata _metadata;
  bool _initialized = false;

  String get _apiKey => Config.getGeminiKey();

  @override
  String get providerId => 'google';

  @override
  String get providerName => 'Google Gemini';

  @override
  String get version => '1.0.0';

  @override
  AIProviderMetadata get metadata => _metadata;

  @override
  List<AICapability> get supportedCapabilities =>
      _metadata.supportedCapabilities;

  @override
  Map<AICapability, List<String>> get availableModels =>
      _metadata.availableModels;

  @override
  Future<bool> initialize(final Map<String, dynamic> config) async {
    if (_initialized) return true;

    try {
      if (_apiKey.trim().isEmpty) return false;
      _initialized = true;
      return await isHealthy();
    } on Exception catch (e) {
      Log.e('[GoogleProvider] Initialization failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isHealthy() async {
    try {
      if (_apiKey.trim().isEmpty) return false;

      // Test API connectivity with a simple list models request
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey';
      final response = await HttpConnector.client.get(Uri.parse(url));

      return response.statusCode == 200;
    } on Exception catch (e) {
      Log.e('[GoogleProvider] Health check failed: $e');
      return false;
    }
  }

  @override
  bool supportsCapability(final AICapability capability) {
    return supportedCapabilities.contains(capability);
  }

  @override
  bool supportsModel(final AICapability capability, final String model) {
    final models = _metadata.getAvailableModels(capability);
    return models.contains(model);
  }

  @override
  String? getDefaultModel(final AICapability capability) {
    return _metadata.getDefaultModel(capability);
  }

  @override
  Future<AIResponse> sendMessage({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
    if (!_initialized || _apiKey.trim().isEmpty) {
      throw Exception('GoogleProvider not initialized or missing API key');
    }

    final modelToUse =
        model ?? getDefaultModel(capability) ?? 'gemini-2.5-flash';

    switch (capability) {
      case AICapability.textGeneration:
      case AICapability.imageAnalysis:
      case AICapability.realtimeConversation:
        return await _sendTextRequest(
          history,
          systemPrompt,
          modelToUse,
          imageBase64,
          imageMimeType,
          additionalParams,
        );
      case AICapability.imageGeneration:
        return await _sendImageGenerationRequest(
          history,
          systemPrompt,
          modelToUse,
          additionalParams,
        );
      default:
        throw UnsupportedError(
          'Capability $capability not supported by GoogleProvider',
        );
    }
  }

  Future<AIResponse> _sendTextRequest(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt,
    final String model,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  ) async {
    try {
      Log.i('Enviando solicitud a Gemini: ${history.length} mensajes');

      // Construir prompt final
      final String finalPrompt = history.isNotEmpty
          ? history.last['content'] ?? ''
          : '';

      // Construir system prompt modificado con metadata de imagen si hay imagen adjunta
      final Map<String, dynamic> systemPromptMap = systemPrompt.toJson();
      if (imageBase64 != null && imageMimeType != null) {
        Log.i('Imagen adjunta detectada, añadiendo metadata al prompt');
        try {
          final instrRoot = systemPromptMap['instructions'];
          if (instrRoot is Map) {
            // Inyectar la instrucción para metadatos de imagen cuando el usuario
            // adjunta una imagen (imageBase64 presente).
            instrRoot['attached_image_metadata_instructions'] = pb
                .imageMetadata(systemPrompt.profile.userName);
          }
        } on Exception catch (_) {}
      }

      // Configuración de generación
      final Map<String, dynamic> generationConfig = {
        'temperature': additionalParams?['temperature'] ?? 0.7,
        'maxOutputTokens': additionalParams?['max_tokens'] ?? 2048,
        'candidateCount': 1,
      };

      // Construir contenido
      final List<Map<String, dynamic>> parts = [];

      // Añadir instrucciones del sistema como primer texto
      final sysJson = jsonEncode(systemPromptMap);
      parts.add({'text': 'System: $sysJson\n\nUser: $finalPrompt'});

      // Añadir imagen si existe
      if (imageBase64 != null && imageMimeType != null) {
        parts.add({
          'inlineData': {'mimeType': imageMimeType, 'data': imageBase64},
        });
      }

      final Map<String, dynamic> requestBody = {
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': generationConfig,
      };

      Log.i('Cuerpo de solicitud Gemini: ${jsonEncode(requestBody)}');

      final baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';
      final url = '$baseUrl/$model:generateContent?key=$_apiKey';

      final response = await HttpConnector.client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      Log.i('Respuesta de Gemini recibida: ${response.body}');

      if (response.statusCode != 200) {
        Log.e('Error en Gemini: ${response.statusCode} - ${response.body}');
        throw Exception('Error de la API de Gemini: ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body);

      if (responseData['candidates'] == null ||
          responseData['candidates'].isEmpty ||
          responseData['candidates'][0]['content'] == null ||
          responseData['candidates'][0]['content']['parts'] == null ||
          responseData['candidates'][0]['content']['parts'].isEmpty) {
        throw Exception('Respuesta inválida de la API de Gemini');
      }

      final content =
          responseData['candidates'][0]['content']['parts'][0]['text']
              as String;

      return AIResponse(text: content);
    } catch (e) {
      Log.e('Error en GoogleProvider._sendTextRequest: $e');
      rethrow;
    }
  }

  Future<AIResponse> _sendImageGenerationRequest(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt,
    final String model,
    final Map<String, dynamic>? additionalParams,
  ) async {
    // Para generación de imágenes con Gemini, seguir el patrón del GeminiService original
    final prompt = history.isNotEmpty
        ? history.last['content'] ?? ''
        : 'Generate an image';

    // Usar systemPrompt con photo_instructions inyectadas como en el servicio original
    final Map<String, dynamic> systemPromptMap = systemPrompt.toJson();
    try {
      final instrRoot = systemPromptMap['instructions'];
      if (instrRoot is Map) {
        // Inyectar photo_instructions para generación de imagen
        instrRoot['photo_instructions'] = pb.imageInstructions(
          systemPrompt.profile.userName,
        );
      }
    } on Exception catch (_) {}

    // Construir mensaje de generación de imagen
    final imageGenerationHistory = [
      {'role': 'user', 'content': prompt},
    ];

    // Usar modelo de imagen específico si está disponible
    final imageModel = model.contains('image') ? model : 'gemini-2.5-flash';

    // Llamar al método _sendTextRequest con el prompt modificado
    return await _sendTextRequest(
      imageGenerationHistory,
      SystemPrompt(
        profile: systemPrompt.profile,
        dateTime: systemPrompt.dateTime,
        instructions: systemPromptMap['instructions'] ?? {},
      ),
      imageModel,
      null,
      null,
      additionalParams,
    );
  }

  @override
  Future<List<String>> getAvailableModelsForCapability(
    final AICapability capability,
  ) async {
    try {
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey';
      final response = await HttpConnector.client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['models'] as List?;

        if (models != null) {
          final supportedForCapability = _metadata.getAvailableModels(
            capability,
          );
          return models.map((final model) => model['name'] as String).where((
            final modelName,
          ) {
            return supportedForCapability.any((final supported) {
              return modelName.toLowerCase().contains(supported.toLowerCase());
            });
          }).toList();
        }
      }

      return _metadata.getAvailableModels(capability);
    } on Exception catch (e) {
      Log.e('[GoogleProvider] Failed to get available models: $e');
      return _metadata.getAvailableModels(capability);
    }
  }

  @override
  Map<String, int> getRateLimits() {
    return _metadata.rateLimits;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
