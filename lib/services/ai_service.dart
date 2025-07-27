import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'gemini_service.dart';
import 'openai_service.dart';
import '../models/ai_response.dart';
import '../models/system_prompt.dart';

abstract class AIService {
  /// Implementación base para enviar mensajes a la IA.
  ///
  /// Si se adjunta imagen, debe combinarse en el mismo bloque/parte que el texto del último mensaje 'user',
  /// siguiendo el patrón multimodal de OpenAI y Gemini (texto + imagen juntos, no por separado).
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
  });

  /// Punto único de entrada para enviar mensajes a la IA con fallback automático.
  static Future<AIResponse> sendMessage(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    String fallbackModel = 'gpt-4.1-mini',
  }) async {
    final m = model ?? 'gemini-2.5-flash';
    AIService? aiService = AIService.select(m);
    if (aiService == null) {
      debugPrint('[AIService.sendMessage] No se pudo encontrar el servicio IA para el modelo: $m');
      return AIResponse(text: '[NO_REPLY]');
    }
    final keys = systemPrompt.toJson().keys.join(', ');
    debugPrint('[AIService.sendMessage] Claves SystemPrompt: $keys');
    final profileKeys = systemPrompt.profile.toJson().keys.join(', ');
    debugPrint('[AIService.sendMessage] Claves SystemPrompt.profile: $profileKeys');
    debugPrint('[AIService.sendMessage] Enviando mensaje a IA con modelo: $m');
    // Guardar logs JSON solo en escritorio (Windows, macOS, Linux)
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final jsonData = {
          'history': history,
          'systemPrompt': systemPrompt.toJson(),
          'model': m,
          if (imageBase64 != null) 'imageBase64': imageBase64,
          if (imageMimeType != null) 'imageMimeType': imageMimeType,
        };
        final jsonStr = const JsonEncoder().convert(jsonData);
        // Guardar el JSON en un archivo temporal dentro del proyecto
        final directory = Directory('debug_json_logs');
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final filePath = '${directory.path}/ai_service_send_$timestamp.json';
        final file = File(filePath);
        file.writeAsStringSync(jsonStr);
        debugPrint('[AIService.sendMessage] JSON enviado guardado en: $filePath');
      } catch (e) {
        debugPrint('[AIService.sendMessage] Error al serializar JSON para log: $e');
      }
    }
    AIResponse response = await aiService.sendMessageImpl(
      history,
      systemPrompt,
      model: m,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );
    // Guardar la respuesta de la IA en un archivo JSON de log solo en escritorio
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final respJson = {'response': response.toJson(), 'model': m, 'timestamp': DateTime.now().toIso8601String()};
        final directory = Directory('debug_json_logs');
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final filePath = '${directory.path}/ai_service_response_$timestamp.json';
        final file = File(filePath);
        file.writeAsStringSync(const JsonEncoder().convert(respJson));
        debugPrint('[AIService.sendMessage] JSON respuesta guardado en: $filePath');
      } catch (e) {
        debugPrint('[AIService.sendMessage] Error al guardar JSON de respuesta: $e');
      }
    }
    bool hasQuotaError(String text) {
      return text.contains('RESOURCE_EXHAUSTED') ||
          text.contains('quota') ||
          text.contains('429') ||
          text.contains('You exceeded your current quota') ||
          text.contains('Error: Falta la API key');
    }

    if (hasQuotaError(response.text) && m != fallbackModel) {
      debugPrint('[AIService.sendMessage] Modelo $m falló por cuota, reintentando con $fallbackModel...');
      aiService = AIService.select(fallbackModel);
      if (aiService == null) {
        debugPrint('[AIService.sendMessage] No se pudo encontrar el servicio IA para el modelo: $fallbackModel');
        return AIResponse(text: '[NO_REPLY]');
      }
      response = await aiService.sendMessageImpl(
        history,
        systemPrompt,
        model: fallbackModel,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );
    }
    return response;
  }

  Future<List<String>> getAvailableModels();

  /// Selecciona el servicio IA adecuado según el modelo
  static AIService? select(String modelId) {
    // Log para depuración
    debugPrint('[AIService.select] Modelo recibido: "$modelId"');
    if (modelId.trim().isEmpty) {
      debugPrint('[AIService.select] El modelo recibido está vacío.');
      return null;
    }
    final normalized = modelId.trim().toLowerCase();
    if (normalized.startsWith('gpt-')) return OpenAIService();
    if (normalized.startsWith('gemini-')) return GeminiService();
    if (normalized.startsWith('imagen-')) return GeminiService();
    debugPrint('[AIService.select] Modelo "$modelId" no reconocido.');
    return null;
  }
}

/// Devuelve la lista combinada de modelos de todos los servicios IA
Future<List<String>> getAllAIModels() async {
  final services = [GeminiService(), OpenAIService()];
  final allModels = <String>[];
  for (final service in services) {
    try {
      final models = await service.getAvailableModels();
      allModels.addAll(models);
    } catch (_) {
      // Si falla un servicio, ignora y sigue
    }
  }
  return allModels;
}
