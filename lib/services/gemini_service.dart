import 'dart:convert';
// import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/ai_response.dart';

class GeminiService implements AIService {
  static final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Obtiene la lista de modelos Gemini disponibles (actualizado julio 2025)
  @override
  Future<List<String>> getAvailableModels() async {
    // Obtiene la lista real de modelos desde el endpoint de Gemini
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final models = <String>[];
      if (data['models'] != null) {
        for (final m in data['models']) {
          if (m['name'] != null) {
            // El nombre viene como 'models/gemini-2.5-pro', extrae solo el id
            final name = m['name'].toString();
            final id = name.replaceFirst('models/', '');
            models.add(id);
          }
        }
      }
      return models;
    } else {
      // Si falla, retorna la lista estática como fallback
      return ['gemini-2.5-pro', 'gemini-2.5-flash'];
    }
  }

  /// Envía un mensaje a Gemini o genera una imagen con Imagen según el modelo seleccionado
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    String systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
  }) async {
    if (_apiKey.trim().isEmpty) {
      return AIResponse(
        text:
            'Error: Falta la API key de Gemini. Por favor, configúrala en el servicio.',
      );
    }
    final selectedModel = (model ?? 'gemini-2.5-pro').trim();
    final headers = {'Content-Type': 'application/json'};
    final endpointBase =
        'https://generativelanguage.googleapis.com/v1beta/models/';
    final endpoint = '$endpointBase$selectedModel:generateContent?key=$_apiKey';
    final url = Uri.parse(endpoint);
    // Construir contents multimodal en orden cronológico
    List<Map<String, dynamic>> contents = [];
    if (systemPrompt.isNotEmpty) {
      contents.add({
        "role": "system",
        "parts": [
          {"text": systemPrompt},
        ],
      });
    }
    for (int i = 0; i < history.length; i++) {
      final role = history[i]['role'] ?? 'user';
      final contentStr = history[i]['content'] ?? '';
      List<Map<String, dynamic>> parts = [];
      if (role == 'user') {
        if (contentStr.isNotEmpty) {
          parts.add({"text": contentStr});
        }
        // Solo añadir imagen al último mensaje user
        if (i == history.length - 1 &&
            imageBase64 != null &&
            imageBase64.isNotEmpty) {
          parts.add({
            "inline_data": {
              "mime_type": imageMimeType ?? 'image/png',
              "data": imageBase64,
            },
          });
        }
        // Si el mensaje user está vacío y no hay imagen, forzar texto para evitar NO_REPLY
        if (parts.isEmpty) {
          parts.add({"text": "Hola"});
        }
      } else {
        if (contentStr.isNotEmpty) {
          parts.add({"text": contentStr});
        }
      }
      contents.add({"role": role, "parts": parts});
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
      final aiResponse = AIResponse(
        text: (text != null && text.trim().isNotEmpty) ? text : '[NO_REPLY]',
      );
      return aiResponse;
    } else {
      return AIResponse(
        text: 'Error al conectar con Gemini: \\n${response.body}',
      );
    }
    // Por seguridad, nunca retorna null
    // throw Exception('Error inesperado en GeminiService');
  }

  // Estimación rápida de tokens (igual que OpenAI)
  int estimateTokens(List<Map<String, String>> history, String systemPrompt) {
    int charCount = systemPrompt.length;
    for (var msg in history) {
      charCount += msg['content']?.length ?? 0;
    }
    return (charCount / 4).round();
  }
}
