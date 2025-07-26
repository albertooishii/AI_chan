import 'dart:convert';
import 'package:flutter/foundation.dart';

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
    String systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
  }) async {
    if (apiKey.trim().isEmpty) {
      return AIResponse(text: 'Error: Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    // Endpoint y headers para OpenAI Assistants v2
    final url = Uri.parse('https://api.openai.com/v1/responses');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'OpenAI-Beta': 'assistants=v2',
    };
    // Construir input multimodal en orden cronológico
    List<Map<String, dynamic>> input = [];
    bool hasImage =
        history.isNotEmpty && history.last['role'] == 'user' && imageBase64 != null && imageBase64.isNotEmpty;
    if (hasImage) {
      // Unificar systemPrompt + historial en un solo bloque de texto
      StringBuffer allText = StringBuffer();
      if (systemPrompt.isNotEmpty) {
        allText.write('[system]: $systemPrompt');
      }
      for (int i = 0; i < history.length; i++) {
        final role = history[i]['role'] ?? 'user';
        final contentStr = history[i]['content'] ?? '';
        if (allText.isNotEmpty) allText.write('\n\n');
        allText.write('[$role]: $contentStr');
      }
      input.add({
        "role": "user",
        "content": [
          {"type": "input_text", "text": allText.toString()},
          {"type": "input_image", "image_url": "data:${imageMimeType ?? 'image/png'};base64,$imageBase64"},
        ],
      });
    } else {
      if (systemPrompt.isNotEmpty) {
        input.add({
          "role": "system",
          "content": [
            {"type": "input_text", "text": systemPrompt},
          ],
        });
      }
      // Unir todos los mensajes en un solo bloque de texto (como JSON o texto plano)
      StringBuffer allText = StringBuffer();
      for (int i = 0; i < history.length; i++) {
        final role = history[i]['role'] ?? 'user';
        final contentStr = history[i]['content'] ?? '';
        if (allText.isNotEmpty) allText.write('\n\n');
        allText.write('[$role]: $contentStr');
      }
      input.add({
        "role": "user",
        "content": [
          {"type": "input_text", "text": allText.toString()},
        ],
      });
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
    // Guardar el JSON del payload enviado para inspección
    /*final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sentFile = File('openai_sent_payload_$timestamp.json');
    await sentFile.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonDecode(body)));*/
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Guardar el JSON completo en la carpeta del proyecto para inspección
      /*final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('openai_response_$timestamp.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));*/

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
            if (item['image_id'] != null && imageId.isEmpty) imageId = item['image_id'];
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
      print(
        'AI Response: ${aiResponse.text}, Image ID: ${aiResponse.imageId}, Revised Prompt: ${aiResponse.revisedPrompt}',
      );
      return aiResponse;
    } else {
      // Guardar el JSON completo en la carpeta del proyecto para inspección
      /*final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('openai_error_response_$timestamp.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(response.body));*/

      debugPrint('[OpenAIService] ERROR: statusCode=${response.statusCode}, body=${response.body}');
      return AIResponse(text: 'Error al conectar con la IA: Status ${response.statusCode} ${response.body}');
    }
  }
}
