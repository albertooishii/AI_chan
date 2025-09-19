import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_metadata.dart';
import 'package:ai_chan/shared/ai_providers/core/services/api_key_manager.dart';
import 'package:ai_chan/shared/domain/models/index.dart';
import 'package:ai_chan/shared/infrastructure/network/http_connector.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';
import 'package:ai_chan/chat/infrastructure/adapters/prompt_builder_service.dart'
    as pb;
import 'package:ai_chan/shared/infrastructure/utils/debug_call_logger/debug_call_logger_io.dart';
import 'package:ai_chan/chat/application/services/tts_voice_management_service.dart'
    as tts_svc;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:ai_chan/shared/ai_providers/core/models/provider_response.dart';
import 'package:ai_chan/shared/ai_providers/core/services/image/image_persistence_service.dart';

/// Google Gemini provider implementation using the new architecture.
/// This provider directly implements HTTP calls to Google AI API without depending on GeminiService.
class GoogleProvider implements IAIProvider, tts_svc.TTSVoiceProvider {
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

  String get _apiKey {
    final key = ApiKeyManager.getNextAvailableKey('gemini');
    if (key == null || key.isEmpty) {
      throw Exception(
        'No valid Gemini API key available. Please configure GEMINI_API_KEYS in environment.',
      );
    }
    return key;
  }

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
  Future<ProviderResponse> sendMessage({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Read API key once per request to avoid multiple calls (and duplicated logs)
    final apiKey = _apiKey;
    if (!_initialized || apiKey.trim().isEmpty) {
      throw Exception('GoogleProvider not initialized or missing API key');
    }

    final modelToUse =
        model ?? getDefaultModel(capability) ?? 'gemini-2.5-flash';

    switch (capability) {
      case AICapability.textGeneration:
      case AICapability.imageAnalysis:
      case AICapability.realtimeConversation:
        final r = await _sendTextRequest(
          history,
          systemPrompt,
          modelToUse,
          imageBase64,
          imageMimeType,
          additionalParams,
          apiKey,
        );
        return ProviderResponse(text: r.text, seed: r.seed, prompt: r.prompt);
      case AICapability.imageGeneration:
        final r2 = await _sendImageGenerationRequest(
          history,
          systemPrompt,
          modelToUse,
          additionalParams,
          apiKey,
        );
        return ProviderResponse(
          text: r2.text,
          seed: r2.seed,
          prompt: r2.prompt,
        );
      default:
        return ProviderResponse(
          text: 'Capability $capability not supported by GoogleProvider',
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
    final String apiKey,
  ) async {
    try {
      // 🔍 DEBUG: Log image handling
      Log.d(
        '[GoogleProvider] _sendTextRequest called - imageBase64: ${imageBase64?.isNotEmpty == true ? "PROVIDED (${imageBase64!.length} chars)" : "NULL/EMPTY"}, additionalParams: $additionalParams',
      );

      Log.i('Enviando solicitud a Gemini: ${history.length} mensajes');

      // Usar la misma lógica que el GeminiService que funciona
      final Map<String, dynamic> systemPromptMap = systemPrompt.toJson();
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
      final url = '$baseUrl/$model:generateContent?key=$apiKey';

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
        // Log.e('Error en Gemini: ${response.statusCode} - ${response.body}');
        // Throw an HttpException so the centralized retry service can
        // recognise HTTP status codes (5xx, 429, etc.) and decide to retry.
        throw HttpException(
          '${response.statusCode} Error de la API de Gemini: ${response.body}',
        );
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

      if (outBase64 != null && outBase64.isNotEmpty) {
        try {
          final saved = await ImagePersistenceService.instance.saveBase64Image(
            outBase64,
          );
          if (saved != null && saved.isNotEmpty) {
            return AIResponse(
              text: (text != null && text.trim().isNotEmpty) ? text : '',
              prompt: imagePrompt ?? '',
            );
          }
        } on Exception catch (e) {
          Log.w('[GoogleProvider] Failed to persist image base64: $e');
        }
      }

      return AIResponse(
        text: (text != null && text.trim().isNotEmpty) ? text : '',
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
    final String apiKey,
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
      apiKey,
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
  Future<ProviderResponse> generateAudio({
    required final String text,
    final String? voice,
    final String? model,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Google TTS not implemented in Enhanced AI yet
    Log.w('[GoogleProvider] TTS not implemented yet - use Google TTS service');
    return ProviderResponse(
      text: 'Google TTS not implemented in Enhanced AI - use legacy service',
    );
  }

  @override
  Future<ProviderResponse> transcribeAudio({
    required final String audioBase64,
    final String? audioFormat,
    final String? model,
    final String? language,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Google STT not implemented in Enhanced AI yet
    Log.w('[GoogleProvider] STT not implemented yet - use Google STT service');
    return ProviderResponse(
      text: 'Google STT not implemented in Enhanced AI - use legacy service',
    );
  }

  @override
  Future<IRealtimeClient?> createRealtimeClient({
    final String? model,
    final void Function(String)? onText,
    final void Function(Uint8List)? onAudio,
    final void Function()? onCompleted,
    final void Function(Object)? onError,
    final void Function(String)? onUserTranscription,
    final Map<String, dynamic>? additionalParams,
  }) async {
    Log.w('[GoogleProvider] Realtime conversation not supported yet');
    // TODO: Implement Google Gemini realtime client when API becomes available
    return null;
  }

  @override
  bool supportsRealtimeForModel(final String? model) {
    // Google Gemini doesn't support realtime conversation yet
    return false;
  }

  @override
  List<String> getAvailableRealtimeModels() {
    // Google Gemini doesn't support realtime conversation yet
    return [];
  }

  @override
  bool get supportsRealtime {
    // Google Gemini doesn't support realtime conversation yet
    return false;
  }

  @override
  String? get defaultRealtimeModel {
    // Google Gemini doesn't support realtime conversation yet
    return null;
  }

  // ========================================
  // VOICE MANAGEMENT - 100% AUTOCONTENIDO
  // ========================================

  /// Get all available voices from Google TTS API
  @override
  Future<List<tts_svc.VoiceInfo>> getAvailableVoices() async {
    try {
      final url = 'https://texttospeech.googleapis.com/v1/voices?key=$_apiKey';
      final response = await HttpConnector.client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final voices = (data['voices'] as List<dynamic>?) ?? [];

        return voices
            .map((final voice) => _createVoiceInfoFromGoogleAPI(voice))
            .where((final voice) => voice.name.isNotEmpty)
            .toList();
      } else {
        Log.w(
          '[GoogleProvider] Failed to fetch voices: ${response.statusCode}',
        );
        return _getFallbackVoices();
      }
    } on Exception catch (e) {
      Log.e('[GoogleProvider] Error fetching voices: $e');
      return _getFallbackVoices();
    }
  }

  /// Convert Google API response to VoiceInfo (Google-specific logic)
  tts_svc.VoiceInfo _createVoiceInfoFromGoogleAPI(
    final Map<String, dynamic> data,
  ) {
    final name = data['name'] ?? '';
    final languageCodes =
        (data['languageCodes'] as List?)?.cast<String>() ?? ['en'];
    final primaryLanguage = languageCodes.isNotEmpty
        ? languageCodes.first
        : 'en';

    return tts_svc.VoiceInfo(
      id: name,
      name: name,
      language: primaryLanguage,
      gender: _convertGoogleGender(data['ssmlGender'] ?? ''),
      description: 'Natural voice',
    );
  }

  /// Convert Google gender format to our standard format (Google-specific logic)
  String _convertGoogleGender(final String googleGender) {
    switch (googleGender.toUpperCase()) {
      case 'FEMALE':
        return 'Femenina';
      case 'MALE':
        return 'Masculina';
      case 'NEUTRAL':
        return 'Neutral';
      default:
        return 'Desconocido';
    }
  }

  /// Fallback voices if API call fails
  List<tts_svc.VoiceInfo> _getFallbackVoices() {
    return [
      const tts_svc.VoiceInfo(
        id: 'es-ES-Neural2-A',
        name: 'es-ES-Neural2-A',
        language: 'es-ES',
        gender: 'Femenina',
      ),
      const tts_svc.VoiceInfo(
        id: 'es-ES-Neural2-B',
        name: 'es-ES-Neural2-B',
        language: 'es-ES',
        gender: 'Masculina',
      ),
      const tts_svc.VoiceInfo(
        id: 'es-ES-Neural2-C',
        name: 'es-ES-Neural2-C',
        language: 'es-ES',
        gender: 'Femenina',
      ),
      const tts_svc.VoiceInfo(
        id: 'es-ES-Neural2-D',
        name: 'es-ES-Neural2-D',
        language: 'es-ES',
        gender: 'Masculina',
      ),
      const tts_svc.VoiceInfo(
        id: 'es-ES-Standard-A',
        name: 'es-ES-Standard-A',
        language: 'es-ES',
        gender: 'Femenina',
      ),
      const tts_svc.VoiceInfo(
        id: 'es-ES-Standard-B',
        name: 'es-ES-Standard-B',
        language: 'es-ES',
        gender: 'Masculina',
      ),
    ];
  }

  /// Get gender of a specific voice (may require API call if not cached)
  String getVoiceGender(final String voiceName) {
    // For Google, we'd need to query the API or cache
    // For now, return based on common patterns
    if (voiceName.contains('-A') || voiceName.contains('-C')) {
      return 'Femenina';
    } else if (voiceName.contains('-B') || voiceName.contains('-D')) {
      return 'Masculina';
    }
    return 'Desconocido';
  }

  /// Get default voice for this provider
  String getDefaultVoice() {
    return 'es-ES-Neural2-A'; // High quality female voice
  }

  /// Get list of voice names only (for compatibility)
  Future<List<String>> getVoiceNames() async {
    final voices = await getAvailableVoices();
    return voices.map((final voice) => voice.name).toList();
  }

  /// Check if a voice is valid for this provider
  Future<bool> isValidVoice(final String voiceName) async {
    final voices = await getAvailableVoices();
    return voices.any(
      (final voice) => voice.name.toLowerCase() == voiceName.toLowerCase(),
    );
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
