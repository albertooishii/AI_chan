import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_metadata.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/http_connector.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/chat/infrastructure/adapters/prompt_builder_service.dart'
    as pb;
import 'package:ai_chan/shared/utils/debug_call_logger/debug_call_logger_io.dart';
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
      // 🔍 DEBUG: Log image handling
      Log.d(
        '[GoogleProvider] _sendTextRequest called - imageBase64: ${imageBase64?.isNotEmpty == true ? "PROVIDED (${imageBase64!.length} chars)" : "NULL/EMPTY"}, additionalParams: $additionalParams',
      );

      Log.i('Enviando solicitud a Gemini: ${history.length} mensajes');

      // Usar la misma lógica que el GeminiService que funciona
      final Map<String, dynamic> systemPromptMap = systemPrompt.toJson();

      // Inyectar instrucciones según el contexto, igual que en GeminiService
      try {
        final instrRoot = systemPromptMap['instructions'];
        if (instrRoot is Map) {
          // Inyectar la instrucción para metadatos de imagen cuando el usuario
          // adjunta una imagen (imageBase64 presente).
          if (imageBase64 != null && imageBase64.isNotEmpty) {
            instrRoot['attached_image_metadata_instructions'] = pb
                .imageMetadata(systemPrompt.profile.userName);
          }
          // Si se solicita generación de imagen explícita, inyectar también la instrucción de 'foto'.
          final enableImageGeneration =
              additionalParams?['enableImageGeneration'] == true;
          if (enableImageGeneration) {
            instrRoot['photo_instructions'] = pb.imageInstructions(
              systemPrompt.profile.userName,
            );
          }
        }
      } on Exception catch (_) {}

      // Construir contenido usando la MISMA estructura que GeminiService (sin duplicación)
      final List<Map<String, dynamic>> contents = [];

      // Añadir un bloque de role=model con el SystemPrompt serializado
      final sysJson = jsonEncode(systemPromptMap);
      contents.add({
        'role': 'model',
        'parts': [
          {'text': sysJson},
        ],
      });

      // Manejar imagen correctamente - imageBase64 viene como parámetro separado
      final bool hasImage = imageBase64 != null && imageBase64.isNotEmpty;

      if (hasImage) {
        // Si hay imagen, enviar el historial SIN duplicar el systemPrompt (ya está en el bloque 'model')
        final StringBuffer allText = StringBuffer();
        for (int i = 0; i < history.length; i++) {
          final role = history[i]['role'] ?? 'user';
          final contentStr = history[i]['content'] ?? '';
          if (allText.isNotEmpty) allText.write('\n\n');
          allText.write('[$role]: $contentStr');
        }

        contents.add({
          'role': 'user',
          'parts': [
            {'text': allText.toString()},
            {
              'inline_data': {
                'mime_type': imageMimeType ?? 'image/png',
                'data': imageBase64,
              },
            },
          ],
        });
      } else {
        // Unir todos los mensajes en un solo bloque de texto SIN duplicar systemPrompt
        final StringBuffer allText = StringBuffer();
        for (int i = 0; i < history.length; i++) {
          final role = history[i]['role'] ?? 'user';
          final contentStr = history[i]['content'] ?? '';
          if (allText.isNotEmpty) allText.write('\n\n');
          allText.write('[$role]: $contentStr');
        }

        final parts = <Map<String, dynamic>>[
          {'text': allText.toString()},
        ];
        contents.add({'role': 'user', 'parts': parts});
      }

      // Configuración de generación (opcional, como en GeminiService)
      final Map<String, dynamic> requestPayload = {'contents': contents};

      // 🔍 DEBUG: Log request payload tal como se envía
      try {
        await debugLogCallPrompt('google_provider_request', requestPayload);
      } on Exception catch (_) {}

      final baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';
      final url = '$baseUrl/$model:generateContent?key=$_apiKey';

      final response = await HttpConnector.client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestPayload),
      );

      // 🔍 DEBUG: Log response tal como se recibe
      try {
        if (response.statusCode == 200) {
          await debugLogCallPrompt(
            'google_provider_response',
            jsonDecode(response.body),
          );
        } else {
          await debugLogCallPrompt('google_provider_error', {
            'status_code': response.statusCode,
            'body': response.body,
          });
        }
      } on Exception catch (_) {}

      if (response.statusCode != 200) {
        Log.e('Error en Gemini: ${response.statusCode} - ${response.body}');
        throw Exception('Error de la API de Gemini: ${response.statusCode}');
      }

      // Usar la misma lógica de parsing que GeminiService
      final data = jsonDecode(response.body);
      String? text;
      String? imagePrompt;
      String? outBase64;
      final candidates = data['candidates'] ?? [];

      if (candidates.isNotEmpty && candidates[0]['content'] != null) {
        final parts = candidates[0]['content']['parts'] ?? [];
        for (final part in parts) {
          if (text == null && part is Map && part['text'] != null) {
            text = part['text'];
          }
          if (outBase64 == null && part is Map && part['inline_data'] != null) {
            final inline = part['inline_data'];
            final mime = (inline['mime_type'] ?? '').toString();
            final dataB64 = inline['data']?.toString();
            if (mime.startsWith('image/') &&
                dataB64 != null &&
                dataB64.isNotEmpty) {
              outBase64 = dataB64;
            }
          }
        }
      }

      return AIResponse(
        text: (text != null && text.trim().isNotEmpty) ? text : '',
        base64: outBase64 ?? '',
        prompt: imagePrompt ?? '',
      );
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
          final modelsList = models
              .map((final model) {
                String modelName = model['name'] as String;
                // Limpiar el prefijo "models/" que viene de la API de Google
                if (modelName.startsWith('models/')) {
                  modelName = modelName.substring(7); // Remover "models/"
                }
                return modelName;
              })
              .where((final modelName) {
                return supportedForCapability.any((final supported) {
                  return modelName.toLowerCase().contains(
                    supported.toLowerCase(),
                  );
                });
              })
              .toList();

          // Aplicar ordenamiento personalizado de Google
          modelsList.sort(_compareGoogleModels);
          return modelsList;
        }
      }

      return _metadata.getAvailableModels(capability);
    } on Exception catch (e) {
      Log.e('[GoogleProvider] Failed to get available models: $e');
      return _metadata.getAvailableModels(capability);
    }
  }

  /// Ordenamiento personalizado para modelos de Google
  /// Prioridad: Gemini versiones más altas primero (2.5 > 1.5), luego Pro > Flash > Lite
  int _compareGoogleModels(final String a, final String b) {
    final priorityA = _getGoogleModelPriority(a);
    final priorityB = _getGoogleModelPriority(b);

    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }

    // Si tienen la misma prioridad, ordenar alfabéticamente descendente (más nuevos primero)
    return b.compareTo(a);
  }

  /// Obtiene la prioridad numérica de un modelo de Google (menor número = mayor prioridad)
  int _getGoogleModelPriority(final String model) {
    final modelLower = model.toLowerCase();

    // Gemini 2.5 serie (versión más alta)
    if (modelLower.contains('gemini-2.5')) {
      if (modelLower.contains('pro') && !modelLower.contains('preview')) {
        return 1;
      }
      if (modelLower.contains('flash') &&
          !modelLower.contains('preview') &&
          !modelLower.contains('lite')) {
        return 2;
      }
      if (modelLower.contains('pro') && modelLower.contains('preview')) {
        return 3;
      }
      if (modelLower.contains('flash') && modelLower.contains('preview')) {
        return 4;
      }
      if (modelLower.contains('lite')) return 5;
      return 6; // Otras variantes de 2.5
    }

    // Gemini 1.5 serie
    if (modelLower.contains('gemini-1.5')) {
      if (modelLower.contains('pro') && !modelLower.contains('preview')) {
        return 7;
      }
      if (modelLower.contains('flash') && !modelLower.contains('preview')) {
        return 8;
      }
      if (modelLower.contains('pro') && modelLower.contains('preview')) {
        return 9;
      }
      if (modelLower.contains('flash') && modelLower.contains('preview')) {
        return 10;
      }
      return 11; // Otras variantes de 1.5
    }

    // Gemini 1.0 o versiones anteriores
    if (modelLower.contains('gemini-1.0') ||
        modelLower.startsWith('gemini') &&
            !modelLower.contains('2.5') &&
            !modelLower.contains('1.5')) {
      if (modelLower.contains('pro')) return 12;
      if (modelLower.contains('flash')) return 13;
      return 14; // Otras variantes de 1.0
    }

    // Modelos especiales
    if (modelLower.contains('image')) return 15;
    if (modelLower.contains('tts')) return 16;
    if (modelLower.contains('vision')) return 17;

    // Resto de modelos
    return 99;
  }

  @override
  Map<String, int> getRateLimits() {
    return _metadata.rateLimits;
  }

  @override
  Future<AIResponse> generateAudio({
    required final String text,
    final String? voice,
    final String? model,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Google TTS not implemented in Enhanced AI yet
    Log.w('[GoogleProvider] TTS not implemented yet - use Google TTS service');
    return AIResponse(
      text: 'Google TTS not implemented in Enhanced AI - use legacy service',
    );
  }

  @override
  Future<AIResponse> transcribeAudio({
    required final String audioBase64,
    final String? audioFormat,
    final String? model,
    final String? language,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Google STT not implemented in Enhanced AI yet
    Log.w('[GoogleProvider] STT not implemented yet - use Google STT service');
    return AIResponse(
      text: 'Google STT not implemented in Enhanced AI - use legacy service',
    );
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
