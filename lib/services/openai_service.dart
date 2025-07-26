import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import '../models/ai_response.dart';
import '../models/system_prompt.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService implements AIService {
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
      // Ordenar por fecha de creación (más nuevo primero)
      gptModels.sort((a, b) => (b['created'] as int).compareTo(a['created'] as int));
      // Retornar solo los id
      return gptModels.map<String>((m) => m['id'].toString()).toList();
    } else {
      throw Exception('Error al obtener modelos: ${response.body}');
    }
  }

  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
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
    final imageId = systemPrompt.profile.imageId;
    if (imageId != null && imageId.isNotEmpty) {
      input.add({"type": "image_generation_call", "id": imageId});
      debugPrint('[OpenAIService.sendMessage] Usando imageId: $imageId');
    }
    input.add({"role": "user", "content": userContent});
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

      String text = '';
      String imageBase64 = '';
      String imageId = '';
      String revisedPrompt = '';
      final output = data['output'] ?? data['data'];
      if (output is List && output.isNotEmpty) {
        // Recorrer todos los bloques y extraer según type con if/else if para mayor legibilidad
        for (final item in output) {
          final type = item['type'];
          if (type == 'image_generation_call') {
            if (item['result'] != null && imageBase64.isEmpty) imageBase64 = item['result'];
            if (item['id'] != null && imageId.isEmpty) imageId = item['id'];
            if (item['revised_prompt'] != null && revisedPrompt.isEmpty) revisedPrompt = item['revised_prompt'];
            if (text.trim().isEmpty && item['text'] != null) text = item['text'];
          } else if (type == 'message') {
            if (item['content'] != null && item['content'] is List) {
              final contentList = item['content'] as List;
              final firstTextBlock = contentList.firstWhere(
                (c) => c['type'] == 'output_text' && c['text'] != null,
                orElse: () => null,
              );
              if (firstTextBlock != null && text.trim().isEmpty) {
                text = firstTextBlock['text'];
              }
            }
          }
        }
      }
      final aiResponse = AIResponse(
        text: (text.trim().isNotEmpty) ? text : '[NO_REPLY]',
        imageBase64: imageBase64,
        imageId: imageId,
        revisedPrompt: revisedPrompt,
      );
      // Log seguro: no imprimir base64 completo
      final logMap = aiResponse.toJson();
      if (logMap['imageBase64'] != null && logMap['imageBase64'].toString().isNotEmpty) {
        final base64 = logMap['imageBase64'] as String;
        logMap['imageBase64'] = '[${base64.length} chars] ${base64.substring(0, 40)}...';
      }
      debugPrint('Respuesta OPEN AI: $logMap');
      return aiResponse;
    } else {
      debugPrint('[OpenAIService] ERROR: statusCode=${response.statusCode}, body=${response.body}');
      return AIResponse(text: 'Error al conectar con la IA: Status ${response.statusCode} ${response.body}');
    }
  }
}
