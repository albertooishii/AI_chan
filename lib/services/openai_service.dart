import 'dart:convert';
import 'ai_service.dart';
import '../models/ai_response.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService implements AIService {
  final String apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';

  /// Transcribe un archivo de audio usando OpenAI Whisper
  Future<String?> transcribeAudio(String filePath) async {
    if (apiKey.trim().isEmpty) {
      throw Exception(
        'Falta la API key de OpenAI. Por favor, configúrala en la app.',
      );
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
      throw Exception(
        'Falta la API key de OpenAI. Por favor, configúrala en la app.',
      );
    }
    if (text.trim().isEmpty) return null;
    final url = Uri.parse('https://api.openai.com/v1/audio/speech');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'input': text,
        'voice': voice,
        'response_format': 'mp3',
      }),
    );
    if (response.statusCode == 200) {
      final dir = outputDir ?? Directory.systemTemp.path;
      final file = File(
        '$dir/ai_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Error TTS OpenAI: ${response.body}');
    }
  }

  // Estimación rápida de tokens (1 token ≈ 4 caracteres)
  int estimateTokens(List<Map<String, String>> history, String systemPrompt) {
    int charCount = systemPrompt.length;
    for (var msg in history) {
      charCount += msg['content']?.length ?? 0;
    }
    return (charCount / 4).round();
  }

  /// Obtiene la lista de modelos disponibles en la API de OpenAI, ordenados por fecha de creación (más nuevo primero)
  @override
  Future<List<String>> getAvailableModels() async {
    if (apiKey.trim().isEmpty) {
      throw Exception(
        'Falta la API key de OpenAI. Por favor, configúrala en la app.',
      );
    }
    const endpoint = 'https://api.openai.com/v1/models';
    final response = await http.get(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List models = data['data'] ?? [];
      // Filtrar solo modelos gpt-*
      final gptModels = models
          .where(
            (m) => m['id'] != null && m['id'].toString().startsWith('gpt-'),
          )
          .toList();
      // Ordenar por fecha de creación (más nuevo primero)
      gptModels.sort(
        (a, b) => (b['created'] as int).compareTo(a['created'] as int),
      );
      // Retornar solo los id
      return gptModels.map<String>((m) => m['id'].toString()).toList();
    } else {
      throw Exception('Error al obtener modelos: ${response.body}');
    }
  }

  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    String systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
  }) async {
    if (apiKey.trim().isEmpty) {
      return AIResponse(
        text:
            'Error: Falta la API key de OpenAI. Por favor, configúrala en la app.',
      );
    }
    // Endpoint y headers
    final url = Uri.parse('https://api.openai.com/v1/responses');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'OpenAI-Beta': 'assistants=v2',
    };
    // Construir input multimodal en orden cronológico
    List<Map<String, dynamic>> input = [];
    if (systemPrompt.isNotEmpty) {
      input.add({
        "role": "system",
        "content": [
          {"type": "input_text", "text": systemPrompt},
        ],
      });
    }
    // Recorrer historial en orden y convertir cada mensaje
    for (int i = 0; i < history.length; i++) {
      final role = history[i]['role'] ?? 'user';
      final contentStr = history[i]['content'] ?? '';
      List<Map<String, dynamic>> contentArr = [];
      if (role == 'user') {
        if (contentStr.isNotEmpty) {
          contentArr.add({"type": "input_text", "text": contentStr});
        }
        // Solo añadir imagen al último mensaje user
        if (i == history.length - 1 &&
            imageBase64 != null &&
            imageBase64.isNotEmpty) {
          contentArr.add({
            "type": "input_image",
            "image_url":
                "data:${imageMimeType ?? 'image/png'};base64,$imageBase64",
          });
        }
        // Si el mensaje user está vacío y no hay imagen, forzar texto para evitar NO_REPLY
        if (contentArr.isEmpty) {
          contentArr.add({"type": "input_text", "text": "Hola"});
        }
      } else {
        // Mensajes assistant/system
        if (contentStr.isNotEmpty) {
          contentArr.add({"type": "input_text", "text": contentStr});
        }
      }
      input.add({"role": role, "content": contentArr});
    }
    int tokens = estimateTokens(history, systemPrompt);
    if (tokens > 128000) {
      return AIResponse(
        text:
            'Error: El mensaje supera el límite de 128,000 tokens permitido por GPT-4.1 y GPT-4o. Reduce la cantidad de mensajes o bloques.',
      );
    }
    final body = jsonEncode({
      "model": model ?? "gpt-4.1-mini",
      "input": input,
      "tools": [
        {"type": "image_generation"},
      ],
    });
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Estructura estándar OpenAI v1/chat/completions:
      // {
      //   id, object, created, model, choices: [ { message: { role, content }, ... } ], ...
      // }
      String? text;
      String? imageBase64;
      String? imageId;
      String? revisedPrompt;
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        if (message != null) {
          final content = message['content'];
          if (content is String) {
            text = content;
          } else if (content is List) {
            // Multimodal: buscar partes
            for (final part in content) {
              if (part is Map &&
                  part['type'] == 'text' &&
                  part['text'] != null) {
                text = part['text'];
              } else if (part is Map &&
                  part['type'] == 'image_url' &&
                  part['image_url'] != null) {
                final url = part['image_url']['url'] as String?;
                if (url != null && url.startsWith('data:')) {
                  // Extraer base64 de la url
                  final base64Match = RegExp(r'base64,(.*)').firstMatch(url);
                  if (base64Match != null) {
                    imageBase64 = base64Match.group(1);
                  }
                }
              }
            }
          }
        }
      }
      final aiResponse = AIResponse(
        text: (text != null && text.trim().isNotEmpty)
            ? text
            : (imageBase64 != null && imageBase64.isNotEmpty)
            ? '[Imagen generada]'
            : '[NO_REPLY]',
        imageBase64: imageBase64 ?? '',
        imageId: imageId ?? '',
        revisedPrompt: revisedPrompt ?? '',
      );
      return aiResponse;
    } else {
      return AIResponse(text: 'Error al conectar con la IA: ${response.body}');
    }
  }
}
