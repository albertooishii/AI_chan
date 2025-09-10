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
import 'dart:io';
import 'package:http/http.dart' as http;

/// OpenAI provider implementation using the new architecture.
/// This provider directly implements HTTP calls to OpenAI API without depending on OpenAIService.
/// Image generation uses text models with tools rather than DALL-E models.
class OpenAIProvider implements IAIProvider {
  OpenAIProvider() {
    _metadata = const AIProviderMetadata(
      providerId: 'openai',
      providerName: 'OpenAI',
      company: 'OpenAI',
      version: '1.0.0',
      description:
          'OpenAI GPT models with vision, image generation via tools, TTS, and STT',
      supportedCapabilities: [
        AICapability.textGeneration,
        AICapability.imageGeneration, // Using text models with tools
        AICapability.imageAnalysis,
        AICapability.audioGeneration, // TTS
        AICapability.audioTranscription, // STT
        AICapability.realtimeConversation,
        AICapability.functionCalling,
      ],
      defaultModels: {
        AICapability.textGeneration: 'gpt-4.1-mini',
        AICapability.imageGeneration:
            'gpt-4.1-mini', // Text model with image generation tool
        AICapability.imageAnalysis: 'gpt-4.1-mini',
        AICapability.audioGeneration: 'gpt-4o-mini-tts',
        AICapability.audioTranscription: 'whisper-1',
        AICapability.realtimeConversation: 'gpt-4o-realtime-preview',
      },
      availableModels: {
        AICapability.textGeneration: ['gpt-5', 'gpt-4.1', 'gpt-4.1-mini'],
        AICapability.imageGeneration: [
          'gpt-5',
          'gpt-4.1',
          'gpt-4.1-mini',
        ], // Text models only
        AICapability.imageAnalysis: ['gpt-5', 'gpt-4.1', 'gpt-4.1-mini'],
        AICapability.audioGeneration: ['gpt-4o-mini-tts', 'tts-1', 'tts-1-hd'],
        AICapability.audioTranscription: ['whisper-1'],
        AICapability.realtimeConversation: ['gpt-4o-realtime-preview'],
      },
      rateLimits: {'requests_per_minute': 3500, 'tokens_per_minute': 200000},
      requiresAuthentication: true,
      requiredConfigKeys: ['OPENAI_API_KEY'],
      maxContextTokens: 128000,
      maxOutputTokens: 4096,
      supportsStreaming: true,
      supportsFunctionCalling: true,
    );
  }
  late final AIProviderMetadata _metadata;
  bool _initialized = false;

  String get _apiKey => Config.getOpenAIKey();

  @override
  String get providerId => 'openai';

  @override
  String get providerName => 'OpenAI';

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
      _initialized = await isHealthy();
      return _initialized;
    } on Exception catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isHealthy() async {
    try {
      final apiKey = _apiKey;
      if (apiKey.trim().isEmpty) return false;

      // Try a simple API call to verify connectivity
      final url = Uri.parse('https://api.openai.com/v1/models');
      final response = await HttpConnector.client.get(
        url,
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      return response.statusCode == 200;
    } on Exception catch (_) {
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
    switch (capability) {
      case AICapability.textGeneration:
      case AICapability.imageAnalysis:
        return await _sendTextRequest(
          history,
          systemPrompt,
          model,
          imageBase64,
          imageMimeType,
          additionalParams,
        );
      case AICapability.imageGeneration:
        return await _sendImageGenerationRequest(
          history,
          systemPrompt,
          model,
          additionalParams,
        );
      case AICapability.audioGeneration:
        return await _sendTTSRequest(history, model, additionalParams);
      default:
        return AIResponse(
          text: 'Capability $capability not supported by OpenAI provider',
        );
    }
  }

  Future<AIResponse> _sendTextRequest(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt,
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  ) async {
    try {
      // 🔍 DEBUG: Log image handling
      Log.d(
        '[OpenAIProvider] _sendTextRequest called - imageBase64: ${imageBase64?.isNotEmpty == true ? "PROVIDED (${imageBase64!.length} chars)" : "NULL/EMPTY"}, additionalParams: $additionalParams',
      );

      // Safety: refuse to call OpenAI endpoints with non-OpenAI model ids.
      final selectedModel =
          model ??
          getDefaultModel(AICapability.textGeneration) ??
          'gpt-4.1-mini';
      final modelNorm = selectedModel.trim().toLowerCase();
      if (modelNorm.isNotEmpty && !modelNorm.startsWith('gpt-')) {
        Log.e(
          '[OpenAIProvider] Called with non-OpenAI model "$selectedModel". Aborting remote call.',
        );
        return AIResponse(
          text:
              'Error: modelo no válido para OpenAI: $selectedModel. Asegúrate de usar un modelo que empiece por "gpt-" o de enrutar la petición al proveedor correcto.',
        );
      }

      if (_apiKey.trim().isEmpty) {
        return AIResponse(
          text:
              'Error: Falta la API key de OpenAI. Por favor, configúrala en la app.',
        );
      }

      final url = Uri.parse('https://api.openai.com/v1/responses');
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2',
      };

      final List<Map<String, dynamic>> input = [];
      final StringBuffer allText = StringBuffer();
      final systemPromptMap = systemPrompt.toJson();

      // Detectar si la petición es explícitamente para generar un AVATAR.
      bool looksLikeAvatar = false;
      try {
        final instrDetect = systemPromptMap['instructions'];
        if (instrDetect is Map) {
          if (instrDetect['is_avatar'] == true) {
            looksLikeAvatar = true;
          }
        }
      } on Exception catch (_) {}

      // Garantizar que las instrucciones de AVATAR y las de FOTO/Metadatos no se mezclen.
      final enableImageGeneration =
          additionalParams?['enableImageGeneration'] == true;
      try {
        final instrRoot = systemPromptMap['instructions'];
        if (instrRoot is Map) {
          if (!looksLikeAvatar) {
            // Inyectar instrucciones sobre foto y metadatos cuando corresponda
            if (enableImageGeneration) {
              instrRoot['photo_instructions'] = pb.imageInstructions(
                systemPrompt.profile.userName,
              );
            }
            if (imageBase64 != null && imageBase64.isNotEmpty) {
              instrRoot['attached_image_metadata_instructions'] = pb
                  .imageMetadata(systemPrompt.profile.userName);
            }
          }
        }
      } on Exception catch (_) {}

      final systemPromptStr = jsonEncode(systemPromptMap);

      // El contenido del sistema proviene de PromptBuilder
      input.add({
        'role': 'system',
        'content': [
          {'type': 'input_text', 'text': systemPromptStr},
        ],
      });

      for (int i = 0; i < history.length; i++) {
        final role = history[i]['role'] ?? 'user';
        final contentStr = history[i]['content'] ?? '';
        if (allText.isNotEmpty) allText.write('\n\n');
        allText.write('[$role]: $contentStr');
      }

      final List<dynamic> userContent = [
        {'type': 'input_text', 'text': allText.toString()},
      ];

      if (imageBase64 != null && imageBase64.isNotEmpty) {
        userContent.add({
          'type': 'input_image',
          'image_url':
              "data:${imageMimeType ?? 'image/png'};base64,$imageBase64",
        });
      }

      // Prefer explicit getter firstAvatar for clarity (primer avatar histórico)
      final avatar = systemPrompt.profile.firstAvatar;

      // El bloque 'role: user' siempre primero
      input.add({'role': 'user', 'content': userContent});

      // Declarar tools vacío
      List<Map<String, dynamic>> tools = [];
      String? previousResponseId;

      // Luego image_generation_call y tools si corresponde
      if (enableImageGeneration) {
        Log.i('[OpenAIProvider] image_generation ACTIVADO');
        tools = [
          {
            'type': 'image_generation',
            'input_fidelity': 'low',
            'moderation': 'low',
            'background': 'opaque',
          },
        ];

        final imageGenCall = <String, dynamic>{};
        // Incluir id solo si existe avatar.seed
        if (avatar != null && avatar.seed != null) {
          final seed = avatar.seed!;
          if (seed.startsWith('resp_')) {
            previousResponseId = seed;
            Log.d('[OpenAIProvider] Seed es previous response ID: $seed');
          } else {
            imageGenCall['type'] = 'image_generation_call';
            imageGenCall['id'] = seed;
            Log.d('[OpenAIProvider] Seed es Image ID: $seed');
            if (looksLikeAvatar) {
              imageGenCall['size'] = '1024x1024';
              Log.d(
                '[OpenAIProvider] Detección: petición tratada como AVATAR -> size=1024x1024',
              );
            }
          }
        } else {
          Log.d(
            '[OpenAIProvider] No hay avatar.seed; no se añadirá el campo id',
          );
          if (looksLikeAvatar) {
            Log.d(
              '[OpenAIProvider] Detección: petición tratada como AVATAR -> size=1024x1024 (aplicado vía tools)',
            );
          }
        }

        // Si es avatar explícito, propagar tamaño al bloque de tools
        if (looksLikeAvatar) {
          try {
            if (tools.isNotEmpty) {
              tools[0]['size'] = '1024x1024';
            }
          } on Exception catch (_) {}
        }

        // Añadir image_generation_call solo si fue inicializado con 'type'
        if (imageGenCall.containsKey('type')) {
          input.add(imageGenCall);
        }
      }

      final Map<String, dynamic> bodyMap = {
        'model': selectedModel,
        'input': input,
        if (tools.isNotEmpty) 'tools': tools,
        if (previousResponseId != null)
          'previous_response_id': previousResponseId,
      };

      // 🔍 DEBUG: Log request payload tal como se envía
      try {
        await debugLogCallPrompt('openai_provider_request', bodyMap);
      } on Exception catch (_) {}

      final response = await HttpConnector.client.post(
        url,
        headers: headers,
        body: jsonEncode(bodyMap),
      );

      // 🔍 DEBUG: Log response tal como se recibe
      try {
        if (response.statusCode == 200) {
          await debugLogCallPrompt(
            'openai_provider_response',
            jsonDecode(response.body),
          );
        } else {
          await debugLogCallPrompt('openai_provider_error', {
            'status_code': response.statusCode,
            'body': response.body,
          });
        }
      } on Exception catch (_) {}

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String text = '';
        String imageBase64Output = '';
        String imageId = '';
        String revisedPrompt = '';
        final String metaPrompt = '';
        final output = data['output'] ?? data['data'];

        String? extractImageBase64FromBlock(final dynamic block) {
          try {
            if (block is Map) {
              if (block['image_base64'] is String) return block['image_base64'];
              if (block['b64_json'] is String) return block['b64_json'];
              if (block['image_url'] is String &&
                  (block['image_url'] as String).startsWith('data:image/')) {
                return block['image_url'];
              }
              if (block['data'] is String &&
                  (block['data'] as String).startsWith('data:image/')) {
                return block['data'];
              }
              if (block['image'] is Map) {
                final img = block['image'] as Map;
                if (img['base64'] is String) return img['base64'];
                if (img['b64_json'] is String) return img['b64_json'];
                if (img['data'] is String &&
                    (img['data'] as String).startsWith('data:image/')) {
                  return img['data'];
                }
              }
            }
          } on Exception catch (_) {}
          return null;
        }

        if (output is List && output.isNotEmpty) {
          for (int i = 0; i < output.length; i++) {
            final item = output[i];
            final type = item['type'];
            if (type == 'image_generation_call') {
              if (item['result'] != null && imageBase64Output.isEmpty) {
                imageBase64Output = item['result'];
              }
              if (item['id'] != null && imageId.isEmpty) imageId = item['id'];
              if (item['revised_prompt'] != null && revisedPrompt.isEmpty) {
                revisedPrompt = item['revised_prompt'];
              }
              if (text.trim().isEmpty && item['text'] != null) {
                text = item['text'];
              }
            } else if (type == 'message') {
              if (item['content'] != null && item['content'] is List) {
                final contentList = item['content'] as List;
                for (final c in contentList) {
                  if (text.trim().isEmpty &&
                      c is Map &&
                      c['type'] == 'output_text' &&
                      c['text'] != null) {
                    text = c['text'];
                  }
                  if (imageBase64Output.isEmpty && c is Map) {
                    final t = (c['type'] ?? '').toString();
                    if (t == 'output_image' ||
                        t == 'image' ||
                        t == 'image_base64' ||
                        t == 'image_url') {
                      final maybe = extractImageBase64FromBlock(c);
                      if (maybe != null && maybe.isNotEmpty) {
                        imageBase64Output = maybe;
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // Elegir seed de forma centralizada: si el modelo soporta multi-turn (gpt-5*),
        // preferir el id de la respuesta; en caso contrario usar el item.id existente.
        try {
          final respId = data['id']?.toString();
          final effectiveModel = selectedModel.toLowerCase();
          if (respId != null &&
              respId.isNotEmpty &&
              effectiveModel.startsWith('gpt-5')) {
            imageId = respId;
            Log.d(
              '[OpenAIProvider] Modelo $effectiveModel -> usando response.id como seed: $imageId',
            );
          } else {
            Log.d(
              '[OpenAIProvider] Modelo $effectiveModel -> usando item.id como seed: $imageId',
            );
          }
        } on Exception catch (_) {}

        final effectivePrompt = (revisedPrompt.trim().isNotEmpty)
            ? revisedPrompt.trim()
            : metaPrompt;

        return AIResponse(
          text: (text.trim().isNotEmpty) ? text : '',
          base64: imageBase64Output,
          seed: imageId,
          prompt: effectivePrompt,
        );
      } else {
        Log.e(
          '[OpenAIProvider] ERROR: statusCode=${response.statusCode}, body=${response.body}',
        );
        return AIResponse(
          text:
              'Error al conectar con la IA: Status ${response.statusCode} ${response.body}',
        );
      }
    } on Exception catch (e) {
      Log.e('[OpenAIProvider] Text request failed: $e');
      return AIResponse(text: 'Error connecting to OpenAI: $e');
    }
  }

  Future<AIResponse> _sendImageGenerationRequest(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt,
    final String? model,
    final Map<String, dynamic>? additionalParams,
  ) async {
    // For image generation, we use text models with image generation tools enabled
    final imageGenerationParams = Map<String, dynamic>.from(
      additionalParams ?? {},
    );
    imageGenerationParams['enableImageGeneration'] = true;

    // Use text generation with enableImageGeneration enabled
    return await _sendTextRequest(
      history,
      systemPrompt,
      model,
      null,
      null,
      imageGenerationParams,
    );
  }

  Future<AIResponse> _sendTTSRequest(
    final List<Map<String, String>> history,
    final String? model,
    final Map<String, dynamic>? additionalParams,
  ) async {
    if (_apiKey.trim().isEmpty) {
      return AIResponse(text: 'Error: Missing OpenAI API key for TTS.');
    }

    // 🔍 DEBUG: Log the received parameters
    Log.d(
      '🎵 [_sendTTSRequest] ⚠️ DEBUGGING: About to check if text is empty...',
      tag: 'OPENAI_TTS',
    );
    Log.d('🎵 [_sendTTSRequest] Called with:', tag: 'OPENAI_TTS');
    Log.d('  - History length: ${history.length}', tag: 'OPENAI_TTS');
    Log.d('  - History content: $history', tag: 'OPENAI_TTS');
    Log.d('  - AdditionalParams: $additionalParams', tag: 'OPENAI_TTS');

    final text = history.isNotEmpty ? history.last['content'] ?? '' : '';
    Log.d(
      '  - Extracted text: "$text" (length: ${text.length})',
      tag: 'OPENAI_TTS',
    );

    Log.d(
      '🎵 [_sendTTSRequest] ⚠️ DEBUGGING: Checking if text.isEmpty...',
      tag: 'OPENAI_TTS',
    );

    if (text.isEmpty) {
      Log.e(
        '🎵 [_sendTTSRequest] ❌ No text provided for TTS',
        tag: 'OPENAI_TTS',
      );
      return AIResponse(text: 'Error: No text provided for TTS.');
    }

    Log.d('🎵 [_sendTTSRequest] ✅ Text validation passed', tag: 'OPENAI_TTS');

    final selectedModel = model ?? 'gpt-4o-mini-tts';
    final voice = additionalParams?['voice'] ?? 'alloy';

    Log.d(
      '🎵 [_sendTTSRequest] ✅ Model and voice determined:',
      tag: 'OPENAI_TTS',
    );
    Log.d('  - Model: $selectedModel (override: $model)', tag: 'OPENAI_TTS');
    Log.d('  - Voice: $voice', tag: 'OPENAI_TTS');

    final payload = {'model': selectedModel, 'input': text, 'voice': voice};

    Log.d('🎵 [_sendTTSRequest] About to send request:', tag: 'OPENAI_TTS');
    Log.d('  - Model: $selectedModel', tag: 'OPENAI_TTS');
    Log.d('  - Voice: $voice', tag: 'OPENAI_TTS');
    Log.d('  - Payload: ${jsonEncode(payload)}', tag: 'OPENAI_TTS');

    Log.d('🎵 [_sendTTSRequest] Calling HttpConnector...', tag: 'OPENAI_TTS');

    try {
      final url = Uri.parse('https://api.openai.com/v1/audio/speech');
      final response = await HttpConnector.client.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      Log.d('🎵 [_sendTTSRequest] Response received:', tag: 'OPENAI_TTS');
      Log.d('  - Status code: ${response.statusCode}', tag: 'OPENAI_TTS');
      Log.d(
        '  - Response body length: ${response.bodyBytes.length} bytes',
        tag: 'OPENAI_TTS',
      );

      if (response.statusCode == 200) {
        final audioBase64 = base64Encode(response.bodyBytes);
        Log.d(
          '🎵 [_sendTTSRequest] ✅ Success! Base64 length: ${audioBase64.length}',
          tag: 'OPENAI_TTS',
        );
        final result = AIResponse(
          text: 'Audio generated successfully',
          base64: audioBase64,
        );
        Log.d(
          '🎵 [_sendTTSRequest] ✅ Returning AIResponse with base64: ${result.base64.isNotEmpty}',
          tag: 'OPENAI_TTS',
        );
        return result;
      } else {
        Log.e(
          '🎵 [_sendTTSRequest] ❌ Error response: ${response.body}',
          tag: 'OPENAI_TTS',
        );
        return AIResponse(
          text: 'Error generating audio: ${response.statusCode}',
        );
      }
    } on Exception catch (e) {
      Log.e('🎵 [_sendTTSRequest] ❌ Exception: $e', tag: 'OPENAI_TTS');
      return AIResponse(text: 'Error connecting to OpenAI TTS: $e');
    }
  }

  @override
  Future<AIResponse> generateAudio({
    required final String text,
    final String? voice,
    final String? model,
    final Map<String, dynamic>? additionalParams,
  }) async {
    Log.d(
      '🎵 [generateAudio] ❗ Este método NO debería llamarse desde sendMessage!',
      tag: 'OPENAI_TTS',
    );
    Log.d('  - text: $text', tag: 'OPENAI_TTS');
    Log.d('  - voice: $voice', tag: 'OPENAI_TTS');
    Log.d('  - model: $model', tag: 'OPENAI_TTS');
    Log.d('  - additionalParams: $additionalParams', tag: 'OPENAI_TTS');

    if (_apiKey.trim().isEmpty) {
      return AIResponse(text: 'Error: Missing OpenAI API key for TTS.');
    }

    if (text.isEmpty) {
      return AIResponse(text: 'Error: No text provided for TTS.');
    }

    // El modelo debe venir del AIProviderManager, no de variables de environment
    final selectedModel =
        model ?? 'gpt-4o-mini-tts'; // Fallback si no se proporciona modelo
    final selectedVoice = voice ?? additionalParams?['voice'] ?? 'alloy';
    final speed = additionalParams?['speed'] ?? 1.0;
    final responseFormat = additionalParams?['response_format'] ?? 'mp3';
    final instructions = additionalParams?['instructions'];

    final payload = {
      'model': selectedModel,
      'input': text,
      'voice': selectedVoice,
      'speed': speed,
      'response_format': responseFormat,
    };

    // Add instructions if provided
    if (instructions != null && instructions.toString().trim().isNotEmpty) {
      payload['instructions'] = instructions.toString();
    }

    // 🔍 LOG DETALLADO: Mostrar payload completo que se envía a OpenAI TTS
    Log.d('🎵 [OPENAI_TTS_PAYLOAD] Enviando petición TTS:', tag: 'OPENAI_TTS');
    Log.d('  - Model: $selectedModel', tag: 'OPENAI_TTS');
    Log.d('  - Voice: $selectedVoice', tag: 'OPENAI_TTS');
    Log.d('  - Speed: $speed', tag: 'OPENAI_TTS');
    Log.d('  - Response Format: $responseFormat', tag: 'OPENAI_TTS');
    Log.d('  - Text length: ${text.length} chars', tag: 'OPENAI_TTS');
    Log.d(
      '  - Text preview: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
      tag: 'OPENAI_TTS',
    );
    if (instructions != null && instructions.toString().trim().isNotEmpty) {
      Log.d(
        '  - Instructions PROVIDED: "${instructions.toString()}"',
        tag: 'OPENAI_TTS',
      );
    } else {
      Log.d('  - Instructions: NOT PROVIDED', tag: 'OPENAI_TTS');
    }
    Log.d(
      '🎵 [OPENAI_TTS_PAYLOAD] Payload completo: ${jsonEncode(payload)}',
      tag: 'OPENAI_TTS',
    );

    try {
      final url = Uri.parse('https://api.openai.com/v1/audio/speech');
      final response = await HttpConnector.client.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      Log.d(
        '🎵 [OPENAI_TTS_RESPONSE] Status: ${response.statusCode}',
        tag: 'OPENAI_TTS',
      );

      if (response.statusCode == 200) {
        Log.d(
          '🎵 [OPENAI_TTS_RESPONSE] ✅ Audio generado exitosamente - Size: ${response.bodyBytes.length} bytes',
          tag: 'OPENAI_TTS',
        );
        final audioBase64 = base64Encode(response.bodyBytes);
        return AIResponse(
          text: 'Audio generated successfully',
          base64: audioBase64,
        );
      } else {
        Log.e(
          '🎵 [OPENAI_TTS_RESPONSE] ❌ Error ${response.statusCode}: ${response.body}',
          tag: 'OPENAI_TTS',
        );
        Log.e(
          '[OpenAIProvider] TTS Error ${response.statusCode}: ${response.body}',
        );
        return AIResponse(
          text: 'Error generating audio: ${response.statusCode}',
        );
      }
    } on Exception catch (e) {
      Log.e('[OpenAIProvider] TTS Exception: $e');
      return AIResponse(text: 'Error connecting to OpenAI TTS: $e');
    }
  }

  @override
  Future<AIResponse> transcribeAudio({
    required final String audioBase64,
    final String? audioFormat,
    final String? model,
    final String? language,
    final Map<String, dynamic>? additionalParams,
  }) async {
    try {
      if (_apiKey.trim().isEmpty) {
        return AIResponse(text: 'Error: Missing OpenAI API key for STT.');
      }

      // Convert base64 to bytes and create temporary file
      final audioBytes = base64Decode(audioBase64);
      final format = audioFormat ?? 'mp3';
      final tempFile = File(
        '${Directory.systemTemp.path}/whisper_${DateTime.now().millisecondsSinceEpoch}.$format',
      );
      await tempFile.writeAsBytes(audioBytes);

      try {
        // Create multipart request using http package directly
        final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
        final request = http.MultipartRequest('POST', url);

        request.headers['Authorization'] = 'Bearer $_apiKey';
        request.fields['model'] = model ?? 'whisper-1';

        if (language != null && language.trim().isNotEmpty) {
          request.fields['language'] = language.trim();
        }

        // Add additional parameters from additionalParams
        if (additionalParams != null) {
          additionalParams.forEach((final k, final v) {
            if (v != null) {
              request.fields[k] = v.toString();
            }
          });
        }

        // Add audio file
        request.files.add(
          await http.MultipartFile.fromPath('file', tempFile.path),
        );

        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Timeout en transcripción de audio',
            const Duration(seconds: 30),
          ),
        );

        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final transcribedText = data['text'] as String? ?? '';
          Log.d(
            '[OpenAIProvider] STT success: ${transcribedText.length} characters',
          );
          return AIResponse(text: transcribedText);
        } else {
          Log.e(
            '[OpenAIProvider] STT Error ${response.statusCode}: ${response.body}',
          );
          return AIResponse(
            text: 'Error transcribing audio: ${response.statusCode}',
          );
        }
      } finally {
        // Clean up temporary file
        try {
          if (tempFile.existsSync()) {
            await tempFile.delete();
          }
        } on Exception catch (e) {
          Log.w('[OpenAIProvider] Error cleaning up temp file: $e');
        }
      }
    } on Exception catch (e) {
      Log.e('[OpenAIProvider] STT Exception: $e');
      return AIResponse(text: 'Error connecting to OpenAI STT: $e');
    }
  }

  @override
  Future<List<String>> getAvailableModelsForCapability(
    final AICapability capability,
  ) async {
    try {
      if (_apiKey.trim().isEmpty) {
        return _metadata.getAvailableModels(capability);
      }

      final url = Uri.parse('https://api.openai.com/v1/models');
      final response = await HttpConnector.client.get(
        url,
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List<dynamic>)
            .map((final model) => model['id'] as String)
            .where((final id) => id.startsWith('gpt-'))
            .toList();

        // Aplicar ordenamiento personalizado de OpenAI
        models.sort(_compareOpenAIModels);
        return models;
      } else {
        return _metadata.getAvailableModels(capability);
      }
    } on Exception catch (_) {
      return _metadata.getAvailableModels(capability);
    }
  }

  /// Ordenamiento personalizado para modelos de OpenAI
  /// Prioridad: GPT-5 sin etiquetas > GPT-5-mini y variantes > GPT-4.1 > GPT-4.1 variantes > GPT-4o > resto
  int _compareOpenAIModels(final String a, final String b) {
    final priorityA = _getOpenAIModelPriority(a);
    final priorityB = _getOpenAIModelPriority(b);

    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }

    // Si tienen la misma prioridad, ordenar alfabéticamente descendente (más nuevos primero)
    return b.compareTo(a);
  }

  /// Obtiene la prioridad numérica de un modelo de OpenAI (menor número = mayor prioridad)
  int _getOpenAIModelPriority(final String model) {
    final modelLower = model.toLowerCase();

    // GPT-5 sin etiquetas (máxima prioridad)
    if (modelLower == 'gpt-5') return 1;

    // GPT-5 variantes por orden de importancia
    if (modelLower.startsWith('gpt-5')) {
      if (modelLower.contains('mini') && !modelLower.contains('-2025-')) {
        return 2;
      }
      if (modelLower.contains('nano') && !modelLower.contains('-2025-')) {
        return 3;
      }
      if (modelLower.contains('chat')) return 4;
      if (modelLower.contains('mini')) return 5; // Con fechas
      if (modelLower.contains('nano')) return 6; // Con fechas
      return 7; // Otras variantes de GPT-5
    }

    // GPT-4.1 sin etiquetas
    if (modelLower == 'gpt-4.1') return 8;

    // GPT-4.1 variantes por orden de importancia
    if (modelLower.startsWith('gpt-4.1')) {
      if (modelLower.contains('mini') && !modelLower.contains('-2025-')) {
        return 9;
      }
      if (modelLower.contains('nano') && !modelLower.contains('-2025-')) {
        return 10;
      }
      if (modelLower.contains('mini')) return 11; // Con fechas
      if (modelLower.contains('nano')) return 12; // Con fechas
      return 13; // Otras variantes de GPT-4.1
    }

    // GPT-4o serie
    if (modelLower.startsWith('gpt-4o')) {
      if (modelLower == 'gpt-4o') return 14;
      if (modelLower.contains('mini') &&
          !modelLower.contains('preview') &&
          !modelLower.contains('audio') &&
          !modelLower.contains('search')) {
        return 15;
      }
      if (modelLower.contains('mini')) return 16; // Otras variantes de mini
      return 17; // Otras variantes de GPT-4o
    }

    // GPT-4 serie
    if (modelLower.startsWith('gpt-4') &&
        !modelLower.startsWith('gpt-4o') &&
        !modelLower.startsWith('gpt-4.1')) {
      if (modelLower == 'gpt-4') return 18;
      if (modelLower.contains('turbo')) return 19;
      return 20; // Otras variantes de GPT-4
    }

    // GPT-3.5 serie
    if (modelLower.startsWith('gpt-3.5')) return 21;

    // Modelos especiales (audio, imagen, etc.) - van al final
    if (modelLower.contains('realtime')) return 22;
    if (modelLower.contains('audio')) return 23;
    if (modelLower.contains('image')) return 24;
    if (modelLower.contains('transcribe')) return 25;
    if (modelLower.contains('search')) return 26;

    // Resto de modelos
    return 99;
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
