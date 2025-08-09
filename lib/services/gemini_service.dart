import 'dart:convert';
// import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';
import '../models/system_prompt.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/ai_response.dart';

class GeminiService implements AIService {
  static final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Obtiene la lista de modelos Gemini disponibles (actualizado julio 2025)
  @override
  Future<List<String>> getAvailableModels() async {
    // Obtiene la lista real de modelos desde el endpoint de Gemini
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final versionGroups = <String, List<String>>{};
      final noVersion = <String>[];
      final versionRegex = RegExp(r'^gemini-(\d+\.\d+)-(\w+)');
      if (data['models'] != null) {
        for (final m in data['models']) {
          if (m['name'] != null) {
            final name = m['name'].toString();
            final id = name.replaceFirst('models/', '');
            if (id.startsWith('gemini-')) {
              final match = versionRegex.firstMatch(id);
              if (match != null) {
                final base = match.group(2) ?? '';
                final key = 'gemini-${match.group(1)}-$base';
                versionGroups.putIfAbsent(key, () => []);
                versionGroups[key]!.add(id);
              } else {
                noVersion.add(id);
              }
            }
          }
        }
      }
      // Ordena los grupos con versión por versión descendente
      final ordered = <String>[];
      final sortedVersionKeys = versionGroups.keys.toList()
        ..sort((a, b) {
          final vA = double.tryParse(RegExp(r'gemini-(\d+\.\d+)').firstMatch(a)?.group(1) ?? '0') ?? 0.0;
          final vB = double.tryParse(RegExp(r'gemini-(\d+\.\d+)').firstMatch(b)?.group(1) ?? '0') ?? 0.0;
          return vB.compareTo(vA);
        });
      for (final key in sortedVersionKeys) {
        final models = versionGroups[key]!;
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
      print('Listado de modelos Gemini ordenados:');
      for (final model in ordered) {
        print(model);
      }
      return ordered;
    } else {
      // Si falla, retorna la lista estática como fallback
      return ['gemini-2.5-pro', 'gemini-2.5-flash'];
    }
  }

  /// Envía un mensaje a Gemini o genera una imagen con Imagen según el modelo seleccionado
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
  }) async {
    if (_apiKey.trim().isEmpty) {
      return AIResponse(text: 'Error: Falta la API key de Gemini. Por favor, configúrala en el servicio.');
    }
    final selectedModel = (model ?? 'gemini-2.5-flash').trim();
    final headers = {'Content-Type': 'application/json'};
    final endpointBase = 'https://generativelanguage.googleapis.com/v1beta/models/';
    final endpoint = '$endpointBase$selectedModel:generateContent?key=$_apiKey';
    final url = Uri.parse(endpoint);
    // Unificar todo el historial en un solo bloque de texto para el content
    List<Map<String, dynamic>> contents = [];
    bool hasImage =
        history.isNotEmpty && history.last['role'] == 'user' && imageBase64 != null && imageBase64.isNotEmpty;
    if (hasImage) {
      // Si hay imagen, enviar el historial completo y el systemPrompt como texto, y la imagen como segundo part
      StringBuffer allText = StringBuffer();
      allText.write('[system]: ${jsonEncode(systemPrompt.toJson())}');
      for (int i = 0; i < history.length; i++) {
        final role = history[i]['role'] ?? 'user';
        final contentStr = history[i]['content'] ?? '';
        if (allText.isNotEmpty) allText.write('\n\n');
        allText.write('[$role]: $contentStr');
      }
      contents.add({
        "role": "user",
        "parts": [
          {"text": allText.toString()},
          {
            "inline_data": {"mime_type": imageMimeType ?? 'image/png', "data": imageBase64},
          },
        ],
      });
    } else {
      // Unir todos los mensajes en un solo bloque de texto (como JSON o texto plano)
      StringBuffer allText = StringBuffer();
      allText.write('[system]: ${jsonEncode(systemPrompt.toJson())}');
      for (int i = 0; i < history.length; i++) {
        final role = history[i]['role'] ?? 'user';
        final contentStr = history[i]['content'] ?? '';
        if (allText.isNotEmpty) allText.write('\n\n');
        allText.write('[$role]: $contentStr');
      }
      contents.add({
        "role": "user",
        "parts": [
          {"text": allText.toString()},
        ],
      });
    }
    int tokens = estimateTokens(history, systemPrompt);
    if (tokens > 128000) {
      return AIResponse(
        text:
            'Error: El mensaje supera el límite de tokens permitido por Gemini. Reduce la cantidad de mensajes o bloques.',
      );
    }
    final body = jsonEncode({"contents": contents});
    final response = await http.post(url, headers: headers, body: body);
    // Procesar respuesta
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String? text;
      final candidates = data['candidates'] ?? [];
      if (candidates.isNotEmpty && candidates[0]['content'] != null) {
        final parts = candidates[0]['content']['parts'] ?? [];
        if (parts.isNotEmpty && parts[0]['text'] != null) {
          text = parts[0]['text'];
        }
      }
      final aiResponse = AIResponse(text: (text != null && text.trim().isNotEmpty) ? text : '[NO_REPLY]');
      return aiResponse;
    } else {
      return AIResponse(text: 'Error al conectar con Gemini: \\n${response.body}');
    }
    // Por seguridad, nunca retorna null
    // throw Exception('Error inesperado en GeminiService');
  }

  // Estimación rápida de tokens (igual que OpenAI)
  int estimateTokens(List<Map<String, String>> history, SystemPrompt systemPrompt) {
    int charCount = jsonEncode(systemPrompt.toJson()).length;
    for (var msg in history) {
      charCount += msg['content']?.length ?? 0;
    }
    return (charCount / 4).round();
  }
}
