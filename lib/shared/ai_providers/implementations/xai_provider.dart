import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_metadata.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/http_connector.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'dart:convert';
import 'dart:async';

/// X.AI Grok provider implementation using the new architecture.
/// This provider directly implements HTTP calls to X.AI API without depending on GrokService.
class XAIProvider implements IAIProvider {
  XAIProvider() {
    _metadata = const AIProviderMetadata(
      providerId: 'xai',
      providerName: 'X.AI Grok',
      company: 'X.AI',
      version: '1.0.0',
      description: 'X.AI Grok models for advanced text generation',
      supportedCapabilities: [AICapability.textGeneration],
      defaultModels: {AICapability.textGeneration: 'grok-beta'},
      availableModels: {
        AICapability.textGeneration: ['grok-beta', 'grok-vision-beta'],
      },
      rateLimits: {'requests_per_minute': 5000, 'tokens_per_minute': 200000},
      requiresAuthentication: true,
      requiredConfigKeys: ['GROK_API_KEY'],
      maxContextTokens: 131072,
      maxOutputTokens: 4096,
      supportsStreaming: false,
      supportsFunctionCalling: false,
    );
  }
  late final AIProviderMetadata _metadata;
  bool _initialized = false;

  String get _apiKey => Config.getGrokKey();

  @override
  String get providerId => 'xai';

  @override
  String get providerName => 'X.AI Grok';

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
      Log.e('[XAIProvider] Initialization failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isHealthy() async {
    try {
      if (_apiKey.trim().isEmpty) return false;

      // Test API connectivity with a simple models request
      final response = await HttpConnector.client.get(
        Uri.parse('https://api.x.ai/v1/models'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );

      return response.statusCode == 200;
    } on Exception catch (e) {
      Log.e('[XAIProvider] Health check failed: $e');
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
      throw Exception('XAIProvider not initialized or missing API key');
    }

    final modelToUse = model ?? getDefaultModel(capability) ?? 'grok-beta';

    switch (capability) {
      case AICapability.textGeneration:
        return await _sendTextRequest(
          history,
          systemPrompt,
          modelToUse,
          imageBase64,
          imageMimeType,
          additionalParams,
        );
      default:
        throw UnsupportedError(
          'Capability $capability not supported by XAIProvider',
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
      Log.i('Enviando solicitud a Grok: ${history.length} mensajes');

      // Construir payload en formato OpenAI-compatible
      final messages = <Map<String, dynamic>>[];

      // Agregar mensaje del sistema
      messages.add({
        'role': 'system',
        'content': jsonEncode(systemPrompt.toJson()),
      });

      // Agregar historial de mensajes
      for (final msg in history) {
        final role = msg['role'] ?? 'user';
        final content = msg['content'] ?? '';
        // Validar y mapear roles para la API de Grok
        final validRole = _validateAndMapRole(role);
        messages.add({'role': validRole, 'content': content});
      }

      final Map<String, dynamic> body = {'model': model, 'messages': messages};

      // Si el usuario adjunta imagen, la incluimos en el último mensaje de usuario
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        final lastUserMessage = messages.lastWhere(
          (final msg) => msg['role'] == 'user',
          orElse: () => {'role': 'user', 'content': ''},
        );
        if (lastUserMessage['content'] is String) {
          lastUserMessage['content'] = [
            {'type': 'text', 'text': lastUserMessage['content']},
            {
              'type': 'image_url',
              'image_url': {
                'url':
                    'data:${imageMimeType ?? 'image/png'};base64,$imageBase64',
              },
            },
          ];
        }
      }

      Log.i('Cuerpo de solicitud Grok: ${jsonEncode(body)}');

      // Use the x.ai (Grok) chat completions endpoint which is OpenAI-compatible.
      final url = Uri.parse('https://api.x.ai/v1/chat/completions');
      final resp = await HttpConnector.client.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      Log.i('Respuesta de Grok recibida: ${resp.body}');

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        String text = '';
        String outBase64 = '';
        String seed = '';
        try {
          // Try OpenAI-style choices -> message -> content
          if (data['choices'] is List && data['choices'].isNotEmpty) {
            final first = data['choices'][0];
            final msg = first['message'] ?? first['delta'];
            if (msg != null) {
              final content = msg['content'];
              if (content is String) {
                text = content;
              } else if (content is Map && content['text'] != null) {
                text = content['text'];
              } else if (content is List) {
                for (final c in content) {
                  try {
                    if (c is Map &&
                        c['type'] != null &&
                        (c['type'] == 'output_text' || c['type'] == 'text')) {
                      text = c['text'] ?? c['content'] ?? text;
                      if (text.isNotEmpty) break;
                    }
                  } on Exception catch (_) {}
                }
              }
            }
            // Some implementations include image data inside choice/result blocks
            try {
              if (first['image'] != null && first['image']['base64'] != null) {
                outBase64 = first['image']['base64'];
              }
              if (first['image_base64'] != null) {
                outBase64 = first['image_base64'];
              }
            } on Exception catch (_) {}
          }

          // Fallback: older style top-level output or image fields
          if (text.isEmpty) {
            if (data['output'] != null) {
              if (data['output'] is String) {
                text = data['output'];
              } else if (data['output'] is Map &&
                  data['output']['text'] != null) {
                text = data['output']['text'];
              }
            }
          }
          if (outBase64.isEmpty) {
            if (data['image_base64'] != null) outBase64 = data['image_base64'];
            if (data['image'] is Map && data['image']['base64'] != null) {
              outBase64 = data['image']['base64'];
            }
          }
          if (seed.isEmpty) {
            if (data['id'] != null) {
              seed = data['id'].toString();
            } else if (data['response_id'] != null) {
              seed = data['response_id'].toString();
            }
          }
        } on Exception catch (_) {}
        return AIResponse(text: text, base64: outBase64, seed: seed);
      } else {
        Log.e('Error en Grok: ${resp.statusCode} - ${resp.body}');
        return AIResponse(
          text: 'Error al conectar con Grok: ${resp.statusCode} ${resp.body}',
        );
      }
    } on Exception catch (e) {
      Log.e('Error en XAIProvider._sendTextRequest: $e');
      return AIResponse(text: 'Error al conectar con Grok: $e');
    }
  }

  /// Valida y mapea roles para asegurar compatibilidad con la API de Grok
  String _validateAndMapRole(final String role) {
    // Roles válidos para la API de Grok (OpenAI-compatible)
    const validRoles = {'system', 'user', 'assistant', 'tool', 'function'};

    if (validRoles.contains(role)) {
      return role;
    }

    // Mapear roles inválidos a roles válidos
    switch (role.toLowerCase()) {
      case 'ia':
        return 'assistant';
      case 'bot':
        return 'assistant';
      case 'ai':
        return 'assistant';
      default:
        // Para cualquier otro role desconocido, usar 'user' como fallback seguro
        return 'user';
    }
  }

  @override
  Future<List<String>> getAvailableModelsForCapability(
    final AICapability capability,
  ) async {
    // Si no hay clave, devolver modelo estático por defecto
    if (_apiKey.trim().isEmpty) {
      return ['grok-3', 'grok-3-mini'];
    }

    try {
      final url = Uri.parse('https://api.x.ai/v1/models');
      final resp = await HttpConnector.client.get(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final List out = (data['data'] ?? data['models'] ?? []);
        final names = <String>[];
        for (final m in out) {
          try {
            if (m is String) {
              names.add(m);
            } else if (m is Map && m['id'] != null) {
              names.add(m['id'].toString());
            }
          } on Exception catch (_) {}
        }
        if (names.isEmpty) {
          return ['grok-3'];
        }
        // Ordenar alfabéticamente descendente (Z-A)
        names.sort((final a, final b) => b.compareTo(a));
        return names;
      }
      Log.w('getAvailableModels failed: ${resp.statusCode}');
      return ['grok-3'];
    } on Exception catch (e) {
      Log.w('getAvailableModels error: $e');
      return ['grok-3'];
    }
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
    // XAI doesn't support TTS
    Log.w('[XAIProvider] TTS not supported by XAI/Grok');
    return AIResponse(text: 'XAI/Grok does not support TTS functionality');
  }

  @override
  Future<AIResponse> transcribeAudio({
    required final String audioBase64,
    final String? audioFormat,
    final String? model,
    final String? language,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // XAI doesn't support STT
    Log.w('[XAIProvider] STT not supported by XAI/Grok');
    return AIResponse(text: 'XAI/Grok does not support STT functionality');
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
