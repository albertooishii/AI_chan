import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'ai_service.dart';
import '../models/ai_response.dart';
import '../models/system_prompt.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService implements AIService {
  /// Obtiene la lista de modelos disponibles en la API de OpenAI, ordenados por fecha de creación (más nuevo primero)
  @override
  Future<List<String>> getAvailableModels() async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    const endpoint = 'https://api.openai.com/v1/models';
    final response = await http.get(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List models = data['data'] ?? [];
      // Filtrar solo modelos gpt-*
      final gptModels = models.where((m) => m['id'] != null && m['id'].toString().startsWith('gpt-')).toList();
      // Agrupar por versión y tipo base (ej. gpt-5, gpt-5-mini, gpt-4.1, gpt-4.1-mini, etc.)
      final groupMap = <String, List<String>>{};
      final noVersion = <String>[];
      final groupRegex = RegExp(r'^(gpt-(\d+(?:\.\d+)?)(?:-(mini|nano|chat|o|realtime|latest))?)');
      for (final m in gptModels) {
        final id = m['id'].toString();
        final match = groupRegex.firstMatch(id);
        if (match != null && match.group(2) != null) {
          final type = match.group(3) ?? '';
          final key = type.isNotEmpty ? 'gpt-${match.group(2)}-$type' : 'gpt-${match.group(2)}';
          groupMap.putIfAbsent(key, () => []);
          groupMap[key]!.add(id);
        } else {
          noVersion.add(id);
        }
      }
      // Ordena los grupos por versión descendente y tipo base alfabéticamente
      final ordered = <String>[];
      final sortedKeys = groupMap.keys.toList()
        ..sort((a, b) {
          final vA = double.tryParse(RegExp(r'gpt-(\d+(?:\.\d+)?)').firstMatch(a)?.group(1) ?? '0') ?? 0.0;
          final vB = double.tryParse(RegExp(r'gpt-(\d+(?:\.\d+)?)').firstMatch(b)?.group(1) ?? '0') ?? 0.0;
          if (vA != vB) return vB.compareTo(vA);
          return a.compareTo(b);
        });
      for (final key in sortedKeys) {
        final models = groupMap[key]!;
        // El modelo base primero, luego variantes alfabéticamente
        models.sort((a, b) {
          if (a == key) return -1;
          if (b == key) return 1;
          return a.compareTo(b);
        });
        ordered.addAll(models);
      }
      // Al final los que no tienen versión, ordenados alfabéticamente
      noVersion.sort();
      ordered.addAll(noVersion);
      debugPrint('Listado de modelos GPT ordenados:');
      for (final model in ordered) {
        debugPrint(model);
      }
      return ordered;
    } else {
      throw Exception('Error al obtener modelos: ${response.body}');
    }
  }

  /// Envía un mensaje a la API de OpenAI y retorna la respuesta AIResponse
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    if (apiKey.trim().isEmpty) {
      return AIResponse(text: 'Error: Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    final url = Uri.parse('https://api.openai.com/v1/responses');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'OpenAI-Beta': 'assistants=v2',
    };
    List<Map<String, dynamic>> input = [];
    StringBuffer allText = StringBuffer();
    final systemPromptStr = jsonEncode(systemPrompt.toJson());
    input.add({
      "role": "system",
      "content": [
        {"type": "input_text", "text": systemPromptStr},
        if (imageBase64 != null && imageBase64.isNotEmpty)
          {
            "type": "input_text",
            "text":
                "Si el usuario ha adjuntado una imagen para analizar, antes de cualquier otra salida escribe una única línea que empiece exactamente con 'IMG_META: ' seguida de un JSON válido con la clave 'prompt' que describa en detalle lo que hay en la imagen que estás viendo. Ejemplo: IMG_META: {\"prompt\": \"<descripción larga y concreta de la imagen que ves>\"}. No uses backticks ni bloques de código. Después de esa línea, responde normalmente al usuario sin repetir el JSON.",
          },
      ],
    });
    for (int i = 0; i < history.length; i++) {
      final role = history[i]['role'] ?? 'user';
      final contentStr = history[i]['content'] ?? '';
      if (allText.isNotEmpty) allText.write('\n\n');
      allText.write('[$role]: $contentStr');
    }
    List<dynamic> userContent = [
      {"type": "input_text", "text": allText.toString()},
    ];
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      userContent.add({"type": "input_image", "image_url": "data:${imageMimeType ?? 'image/png'};base64,$imageBase64"});
    }
    final avatar = systemPrompt.profile.avatar;
    // El bloque 'role: user' siempre primero
    input.add({"role": "user", "content": userContent});
    // Declarar tools vacío
    List<Map<String, dynamic>> tools = [];
    // Luego image_generation_call y tools si corresponde
    if (enableImageGeneration) {
      debugPrint('[OpenAIService.sendMessage] image_generation ACTIVADO');
      tools = [
        {"type": "image_generation"},
      ];
      // Añadir image_generation_call solo si hay avatar y seed
      if (avatar != null && avatar.seed != null && avatar.seed!.isNotEmpty) {
        final imageGenCall = {"type": "image_generation_call", "id": avatar.seed};
        input.add(imageGenCall);
        debugPrint('[OpenAIService.sendMessage] Usando imageId: ${avatar.seed}');
      }
    } else {
      debugPrint('[OpenAIService.sendMessage] image_generation DESACTIVADO');
    }
    int tokens = estimateTokens(history, systemPrompt);
    if (tokens > 128000) {
      return AIResponse(
        text:
            'Error: El mensaje supera el límite de 128,000 tokens permitido por GPT-5 y GPT-4o. Reduce la cantidad de mensajes o bloques.',
      );
    }
    final Map<String, dynamic> bodyMap = {
      "model": model ?? "gpt-4.1-mini", // default OpenAI cuando se fuerza imagen, pero app usa gemini para texto
      "input": input,
      if (tools.isNotEmpty) "tools": tools,
      // Nota: No incluir 'modalities' aquí; algunos modelos del endpoint /responses no lo soportan
    };
    final body = jsonEncode(bodyMap);

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // (Logging sustituido) Ejemplo de cómo usar ahora debugLogCallPrompt para registrar la respuesta.
      // Mantener comentado para no afectar rendimiento en producción.
      /*
      await debugLogCallPrompt('openai_response', {
        'api_response': data,
        'model': model ?? 'gpt-4.1-mini',
        'timestamp': DateTime.now().toIso8601String(),
      });
      */
      String text = '';
      String imageBase64 = '';
      String imageId = '';
      String revisedPrompt = '';
      String metaPrompt = '';
      final output = data['output'] ?? data['data'];
      String? extractImageBase64FromBlock(dynamic block) {
        try {
          if (block is Map) {
            // formatos potenciales
            if (block['image_base64'] is String) return block['image_base64'];
            if (block['b64_json'] is String) return block['b64_json'];
            if (block['image_url'] is String && (block['image_url'] as String).startsWith('data:image/')) {
              return block['image_url'];
            }
            if (block['data'] is String && (block['data'] as String).startsWith('data:image/')) {
              return block['data'];
            }
            if (block['image'] is Map) {
              final img = block['image'] as Map;
              if (img['base64'] is String) return img['base64'];
              if (img['b64_json'] is String) return img['b64_json'];
              if (img['data'] is String && (img['data'] as String).startsWith('data:image/')) return img['data'];
            }
          }
        } catch (_) {}
        return null;
      }

      if (output is List && output.isNotEmpty) {
        // Recorrer todos los bloques y extraer según type con if/else if para mayor legibilidad
        for (int i = 0; i < output.length; i++) {
          final item = output[i];
          final type = item['type'];
          if (type == 'image_generation_call') {
            if (item['result'] != null && imageBase64.isEmpty) imageBase64 = item['result'];
            if (item['id'] != null && imageId.isEmpty) imageId = item['id'];
            if (item['revised_prompt'] != null && revisedPrompt.isEmpty) revisedPrompt = item['revised_prompt'];
            if (text.trim().isEmpty && item['text'] != null) text = item['text'];
          } else if (type == 'message') {
            if (item['content'] != null && item['content'] is List) {
              final contentList = item['content'] as List;
              for (final c in contentList) {
                if (text.trim().isEmpty && c is Map && c['type'] == 'output_text' && c['text'] != null) {
                  text = c['text'];
                }
                if (imageBase64.isEmpty && c is Map) {
                  final t = (c['type'] ?? '').toString();
                  if (t == 'output_image' || t == 'image' || t == 'image_base64' || t == 'image_url') {
                    final maybe = extractImageBase64FromBlock(c);
                    if (maybe != null && maybe.isNotEmpty) {
                      imageBase64 = maybe;
                    }
                  }
                }
              }
            }
          }
        }
      }
      // Extraer IMG_META si viene en el texto (análisis de imagen) y limpiar esa línea
      if (text.trim().isNotEmpty) {
        try {
          final metaRegex = RegExp(r'^\s*IMG_META\s*:\s*(\{.*\})\s*$', multiLine: true);
          final match = metaRegex.firstMatch(text);
          if (match != null && match.groupCount >= 1) {
            final jsonStr = match.group(1);
            if (jsonStr != null && jsonStr.trim().isNotEmpty) {
              final meta = jsonDecode(jsonStr);
              if (meta is Map && meta['prompt'] is String && (meta['prompt'] as String).trim().isNotEmpty) {
                metaPrompt = (meta['prompt'] as String).trim();
              } else if (meta is Map && meta['caption'] is String && (meta['caption'] as String).trim().isNotEmpty) {
                metaPrompt = (meta['caption'] as String).trim();
              }
              // quitar la línea completa de IMG_META del texto
              final lines = text.split('\n');
              lines.removeWhere((l) => l.contains('IMG_META:'));
              text = lines.join('\n').trim();
            }
          }
        } catch (_) {}
      }

      // Para generación usamos revised_prompt; para análisis usamos metaPrompt
      final effectivePrompt = (revisedPrompt.trim().isNotEmpty) ? revisedPrompt.trim() : metaPrompt;
      final aiResponse = AIResponse(
        text: (text.trim().isNotEmpty) ? text : '',
        base64: imageBase64,
        seed: imageId,
        prompt: effectivePrompt,
      );
      return aiResponse;
    } else {
      debugPrint('[OpenAIService] ERROR: statusCode=${response.statusCode}, body=${response.body}');
      return AIResponse(text: 'Error al conectar con la IA: Status ${response.statusCode} ${response.body}');
    }
  }

  final String apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';

  /// Transcribe un archivo de audio usando OpenAI Whisper
  Future<String?> transcribeAudio(String filePath) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-1'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['text'] as String?;
    } else {
      throw Exception('Error STT OpenAI: ${response.body}');
    }
  }

  /// Genera un archivo de voz usando OpenAI TTS
  Future<File?> textToSpeech({
    required String text,
    String voice = 'nova',
    String model = 'tts-1',
    String? outputDir,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    if (text.trim().isEmpty) return null;
    final url = Uri.parse('https://api.openai.com/v1/audio/speech');
    final response = await http.post(
      url,
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({'model': model, 'input': text, 'voice': voice, 'response_format': 'mp3'}),
    );
    if (response.statusCode == 200) {
      final dir = outputDir ?? Directory.systemTemp.path;
      final file = File('$dir/ai_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Error TTS OpenAI: ${response.body}');
    }
  }

  // Estimación rápida de tokens (1 token ≈ 4 caracteres)
  int estimateTokens(List<Map<String, String>> history, SystemPrompt systemPrompt) {
    int charCount = jsonEncode(systemPrompt.toJson()).length;
    for (var msg in history) {
      charCount += msg['content']?.length ?? 0;
    }
    return (charCount / 4).round();
  }
}
