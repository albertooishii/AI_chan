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
        AICapability.audioGeneration: 'tts-1',
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
        AICapability.audioGeneration: ['tts-1', 'tts-1-hd'],
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

      final response = await HttpConnector.client.post(
        url,
        headers: headers,
        body: jsonEncode(bodyMap),
      );

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
    // For image generation, we use text models with a specific prompt
    final prompt = history.isNotEmpty
        ? history.last['content'] ?? ''
        : 'Generate an image';

    final imageGenerationHistory = [
      {
        'role': 'user',
        'content':
            'Generate a detailed image based on this description: $prompt',
      },
    ];

    final imageSystemPrompt = SystemPrompt(
      profile: AiChanProfile(
        userName: '',
        aiName: '',
        userBirthdate: null,
        aiBirthdate: null,
        biography: const {},
        appearance: const {},
      ),
      dateTime: DateTime.now(),
      instructions: const {
        'raw': 'Generate an image based on the conversation context.',
      },
    );

    // Use text generation with special prompt for image generation
    return await _sendTextRequest(
      imageGenerationHistory,
      imageSystemPrompt,
      model,
      null,
      null,
      additionalParams,
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

    final text = history.isNotEmpty ? history.last['content'] ?? '' : '';
    if (text.isEmpty) {
      return AIResponse(text: 'Error: No text provided for TTS.');
    }

    final selectedModel = model ?? 'tts-1';
    final voice = additionalParams?['voice'] ?? 'alloy';

    final payload = {'model': selectedModel, 'input': text, 'voice': voice};

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

      if (response.statusCode == 200) {
        final audioBase64 = base64Encode(response.bodyBytes);
        return AIResponse(
          text: 'Audio generated successfully',
          base64: audioBase64,
        );
      } else {
        return AIResponse(
          text: 'Error generating audio: ${response.statusCode}',
        );
      }
    } on Exception catch (e) {
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
    if (_apiKey.trim().isEmpty) {
      return AIResponse(text: 'Error: Missing OpenAI API key for TTS.');
    }

    if (text.isEmpty) {
      return AIResponse(text: 'Error: No text provided for TTS.');
    }

    final selectedModel = model ?? 'tts-1';
    final selectedVoice = voice ?? additionalParams?['voice'] ?? 'alloy';
    final speed = additionalParams?['speed'] ?? 1.0;

    final payload = {
      'model': selectedModel,
      'input': text,
      'voice': selectedVoice,
      'speed': speed,
    };

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

      if (response.statusCode == 200) {
        final audioBase64 = base64Encode(response.bodyBytes);
        return AIResponse(
          text: 'Audio generated successfully',
          base64: audioBase64,
        );
      } else {
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

        models.sort((final a, final b) => b.compareTo(a));
        return models;
      } else {
        return _metadata.getAvailableModels(capability);
      }
    } on Exception catch (_) {
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
