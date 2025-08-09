import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import '../models/ai_response.dart';
import '../models/system_prompt.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService implements AIService {
  /// Inicia una sesión de conversación en tiempo real con OpenAI Realtime API
  Future<void> startRealtimeCall({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required void Function(String textChunk) onText,
    void Function(String reasoning)? onReasoning,
    void Function(String summary)? onSummary,
    void Function()? onDone,
    String model = 'gpt-4o-realtime-preview',
    List<int>? audioBytes,
    String audioFormat = 'wav',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    // 1. Crear sesión realtime
    final sessionUrl = Uri.parse('https://api.openai.com/v1/realtime/sessions');
    final sessionResp = await http.post(
      sessionUrl,
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": "gpt-4o-realtime", // Forzado según docs
        "modalities": ["audio", "text"],
        "instructions": systemPrompt.toString(),
      }),
    );
    if (sessionResp.statusCode != 200) {
      throw Exception('Error creando sesión realtime: ${sessionResp.body}');
    }
    debugPrint('[OpenAIService] Respuesta creación sesión: ${sessionResp.body}');
    final sessionData = jsonDecode(sessionResp.body);
    final sessionId = sessionData['id'];
    if (sessionId == null) throw Exception('No se pudo obtener sessionId realtime');

    // 2. Enviar solo audio si se proporciona (no enviar evento tipo 'text')
    if (audioBytes == null || audioBytes.isEmpty) {
      throw Exception('No se proporcionó audioBytes del micrófono para la llamada realtime.');
    }
    final audioEventUrl = Uri.parse('https://api.openai.com/v1/realtime/sessions/$sessionId/events');
    final audioBase64 = base64Encode(audioBytes);
    final resp = await http.post(
      audioEventUrl,
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({"type": "audio", "audio": audioBase64, "audio_format": audioFormat}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Error enviando audio realtime: ${resp.body}');
    }

    // 3. Conectarse al stream de eventos
    final streamEventUrl = Uri.parse('https://api.openai.com/v1/realtime/sessions/$sessionId/events');
    final request = http.Request('GET', streamEventUrl);
    request.headers['Authorization'] = 'Bearer $apiKey';
    final streamedResp = await request.send();
    if (streamedResp.statusCode != 200) {
      throw Exception('Error conectando al stream realtime: ${streamedResp.statusCode}');
    }
    // Procesar los eventos en tiempo real
    await for (final chunk in streamedResp.stream.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        if (line.trim().isEmpty) continue;
        try {
          final event = jsonDecode(line);
          final type = event['type'];
          if (type == 'message_part' && event['text'] != null) {
            onText(event['text']);
          } else if (type == 'reasoning_summary_part' && event['text'] != null) {
            if (onReasoning != null) onReasoning(event['text']);
          } else if (type == 'summary_part' && event['text'] != null) {
            if (onSummary != null) onSummary(event['text']);
          } else if (type == 'done') {
            if (onDone != null) onDone();
            break;
          }
        } catch (e) {
          debugPrint('Error procesando chunk realtime: $e');
        }
      }
    }
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
      userContent.add({
        "type": "input_image",
        "image_url": "data:${imageMimeType ?? 'image/png'};base64,$imageBase64",
        "detail": "high",
      });
    }
    final avatar = systemPrompt.profile.avatar;
    // El bloque 'role: user' siempre primero
    input.add({"role": "user", "content": userContent});
    // Luego image_generation_call si existe
    if (avatar != null && avatar.seed != null && avatar.seed!.isNotEmpty) {
      final imageGenCall = {"type": "image_generation_call", "id": avatar.seed};
      input.add(imageGenCall);
      debugPrint('[OpenAIService.sendMessage] Usando imageId: ${avatar.seed}');
    }
    int tokens = estimateTokens(history, systemPrompt);
    if (tokens > 128000) {
      return AIResponse(
        text:
            'Error: El mensaje supera el límite de 128,000 tokens permitido por GPT-5 y GPT-4o. Reduce la cantidad de mensajes o bloques.',
      );
    }
    final body = jsonEncode({
      "model": model ?? "gpt-5-nano",
      "input": input,
      "tools": [
        {"type": "image_generation"},
        /*{"type": "web_search_preview"},*/
      ],
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Guardar la respuesta REAL de la API en un archivo JSON de log solo en escritorio
      /*if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        try {
          final respJson = {
            'api_response': data,
            'model': model ?? "gpt-5-nano",
            'timestamp': DateTime.now().toIso8601String(),
          };
          final directory = Directory('debug_json_logs');
          if (!directory.existsSync()) {
            directory.createSync(recursive: true);
          }
          final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
          final filePath = '${directory.path}/openai_service_response_$timestamp.json';
          final file = File(filePath);
          file.writeAsStringSync(const JsonEncoder().convert(respJson));
          debugPrint('[OpenAIService.sendMessageImpl] JSON respuesta REAL guardado en: $filePath');
        } catch (e) {
          debugPrint('[OpenAIService.sendMessageImpl] Error al guardar JSON de respuesta: $e');
        }
      }*/
      String text = '';
      String imageBase64 = '';
      String imageId = '';
      String revisedPrompt = '';
      final output = data['output'] ?? data['data'];
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
        base64: imageBase64,
        seed: imageId,
        prompt: revisedPrompt,
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
