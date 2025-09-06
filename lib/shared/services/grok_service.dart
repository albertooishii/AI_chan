import 'dart:convert';
import 'package:ai_chan/core/http_connector.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

/// Servicio mínimo para Grok (Grok-3). Implementación esqueleto basada en
/// el patrón de OpenAI/Gemini en este repo. Completar según la API real.
class GrokService implements AIService {
  String get _apiKey {
    final key = Config.getGrokKey();
    return key;
  }

  @override
  Future<List<String>> getAvailableModels() async {
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
        return names;
      }
      Log.w('[GrokService] getAvailableModels failed: ${resp.statusCode}');
      return ['grok-3'];
    } on Exception catch (e) {
      Log.w('[GrokService] getAvailableModels error: $e');
      return ['grok-3'];
    }
  }

  @override
  Future<AIResponse> sendMessageImpl(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    if (_apiKey.trim().isEmpty) {
      return AIResponse(
        text: 'Error: Falta la API key de Grok. Configura GROK_API_KEY.',
      );
    }

    final selectedModel = (model ?? 'grok-3').trim();

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

    final Map<String, dynamic> body = {
      'model': selectedModel,
      'messages': messages,
    };

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
              'url': 'data:${imageMimeType ?? 'image/png'};base64,$imageBase64',
            },
          },
        ];
      }
    }

    try {
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
        Log.e('[GrokService] Error ${resp.statusCode}: ${resp.body}');
        return AIResponse(
          text: 'Error al conectar con Grok: ${resp.statusCode} ${resp.body}',
        );
      }
    } on Exception catch (e) {
      Log.e('[GrokService] Exception: $e');
      return AIResponse(text: 'Error al conectar con Grok: $e');
    }
  }

  int estimateTokens(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt,
  ) {
    int charCount = jsonEncode(systemPrompt.toJson()).length;
    for (final msg in history) {
      charCount += msg['content']?.length ?? 0;
    }
    return (charCount / 4).round();
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
}
