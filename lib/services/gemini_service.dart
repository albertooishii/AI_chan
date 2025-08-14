import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';
import '../models/system_prompt.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/ai_response.dart';

class GeminiService implements AIService {
  static String get _primaryKey => dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
  static String get _fallbackKey => dotenv.env['GEMINI_API_KEY_FALLBACK']?.trim() ?? '';
  // Recuerda qué clave funcionó la última vez para priorizarla en siguientes llamadas
  static bool _preferFallback = false;

  /// Obtiene la lista de modelos Gemini disponibles (actualizado julio 2025)
  @override
  Future<List<String>> getAvailableModels() async {
    // Obtiene la lista real de modelos desde el endpoint de Gemini con fallback de API key
    bool isQuotaLike(int code, String body) {
      if (code == 403 || code == 429) return true;
      return false;
    }

    Future<http.Response> getWithKey(String key) async {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$key');
      return await http.get(url);
    }

    http.Response response;
    final primary = _primaryKey;
    final fallback = _fallbackKey;
    if (primary.isEmpty && fallback.isEmpty) {
      // Sin clave, retorna listado estático
      return ['gemini-2.5-pro', 'gemini-2.5-flash'];
    }
    // Elige el orden de prueba en función de la preferencia actual
    final firstKey = (_preferFallback && fallback.isNotEmpty) ? fallback : (primary.isNotEmpty ? primary : fallback);
    final secondKey = (firstKey == primary) ? fallback : primary;
    String usedKey = firstKey;
    response = await getWithKey(usedKey);
    if (response.statusCode != 200 && secondKey.isNotEmpty && isQuotaLike(response.statusCode, response.body)) {
      debugPrint('[Gemini] ${response.statusCode} con primera clave; probando la alternativa.');
      final r2 = await getWithKey(secondKey);
      if (r2.statusCode == 200) {
        // Éxito con la alternativa => actualizar preferencia
        _preferFallback = (secondKey == fallback);
        usedKey = secondKey;
        response = r2;
      } else {
        // Si también falla, mantener la respuesta original
        response = r2;
      }
    } else if (response.statusCode == 200) {
      // Éxito con la primera => fijar preferencia
      _preferFallback = (usedKey == fallback);
    }
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
      debugPrint('Listado de modelos Gemini ordenados:');
      for (final model in ordered) {
        debugPrint(model);
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
    bool enableImageGeneration = false,
  }) async {
    final primary = _primaryKey;
    final fallback = _fallbackKey;
    if (primary.isEmpty && fallback.isEmpty) {
      return AIResponse(text: 'Error: Falta la API key de Gemini. Por favor, configúrala en el servicio.');
    }
    final selectedModel = (model ?? 'gemini-2.5-flash').trim();
    final headers = {'Content-Type': 'application/json'};
    final endpointBase = 'https://generativelanguage.googleapis.com/v1beta/models/';
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
      // Instrucción suave: incluir una línea de metadatos de la imagen para mantener el hilo conversacional
      allText.write(
        '\n\n[meta_instruction]: Primero devuelve una línea única que empiece por "IMG_META:" seguida de un JSON compacto con {"prompt":"descripción en español coloquial de la imagen generada o analizada", "scene":"", "outfit":"", "pose":"", "style":"", "nsfw":false, "camera":"", "time":"", "lighting":""}. No limites la longitud arbitrariamente; usa lo que consideres adecuado. Después de esa línea, escribe tu mensaje normal en 1-2 frases.',
      );
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
      // Ignorar enableImageGeneration para Gemini (no generamos IMAGEN aquí). Mantener solo texto.
      // Preparar partes con texto. Si procede, puede venir una imagen del usuario para análisis (hasImage arriba).
      final parts = <Map<String, dynamic>>[
        {"text": allText.toString()},
      ];
      // No adjuntamos avatar de referencia para generación (desactivada en Gemini).
      contents.add({"role": "user", "parts": parts});
    }
    // Ya no imponemos corte local por tokens: dejamos que Gemini gestione límites reales.
    // (Antes: se devolvía error si tokens > 128000)
    // Configuración de generación: cuando queremos imagen, pedir texto+imagen
    // max_output_tokens eliminado: la API estándar de Gemini usa generationConfig (opcional)
    final Map<String, dynamic> requestPayload = {"contents": contents};
    final body = jsonEncode(requestPayload);

    Future<AIResponse> parseAndBuild(String respBody) async {
      final data = jsonDecode(respBody);
      String? text;
      String? imagePrompt;
      String? outBase64;
      final candidates = data['candidates'] ?? [];
      if (candidates.isNotEmpty && candidates[0]['content'] != null) {
        final parts = candidates[0]['content']['parts'] ?? [];
        for (final part in parts) {
          if (text == null && part is Map && part['text'] != null) {
            text = part['text'];
          }
          if (outBase64 == null && part is Map && part['inline_data'] != null) {
            final inline = part['inline_data'];
            final mime = (inline['mime_type'] ?? '').toString();
            final dataB64 = inline['data']?.toString();
            if (mime.startsWith('image/') && dataB64 != null && dataB64.isNotEmpty) {
              outBase64 = dataB64;
            }
          }
        }
        // Extraer IMG_META JSON si existe en el primer bloque de texto
        if (text != null && text.isNotEmpty) {
          try {
            final metaMatch = RegExp(r'^\s*IMG_META:\s*(\{.+\})\s*$', multiLine: true).firstMatch(text);
            if (metaMatch != null) {
              final jsonStr = metaMatch.group(1);
              if (jsonStr != null) {
                final meta = jsonDecode(jsonStr);
                final pr = (meta['prompt'] ?? meta['caption'] ?? '').toString();
                if (pr.isNotEmpty) imagePrompt = pr;
              }
            }
          } catch (_) {}
        }
      }
      return AIResponse(
        text: (text != null && text.trim().isNotEmpty) ? text : '',
        base64: outBase64 ?? '',
        prompt: imagePrompt ?? '',
      );
    }

    Future<AIResponse> sendToModel(String modelId) async {
      bool isQuotaLike(int code, String body) {
        if (code == 403 || code == 429) return true;
        return false;
      }

      Future<http.Response> doPost(String key) {
        final mUrl = Uri.parse('$endpointBase$modelId:generateContent?key=$key');
        return http.post(mUrl, headers: headers, body: body);
      }

      // Determina el orden según preferencia y disponibilidad
      final firstKey = (_preferFallback && fallback.isNotEmpty) ? fallback : (primary.isNotEmpty ? primary : fallback);
      final secondKey = (firstKey == primary) ? fallback : primary;

      String keyUsed = firstKey;
      http.Response resp = await doPost(keyUsed);
      if (resp.statusCode != 200 && secondKey.isNotEmpty && isQuotaLike(resp.statusCode, resp.body)) {
        debugPrint('[Gemini] ${resp.statusCode} con primera clave; reintentando con alternativa.');
        final r2 = await doPost(secondKey);
        if (r2.statusCode == 200) {
          _preferFallback = (secondKey == fallback);
          keyUsed = secondKey;
          resp = r2;
        } else {
          resp = r2; // conservar el último error
        }
      } else if (resp.statusCode == 200) {
        _preferFallback = (keyUsed == fallback);
      }

      if (resp.statusCode == 200) {
        return await parseAndBuild(resp.body);
      }
      final bodyPreview = resp.body.length > 500 ? resp.body.substring(0, 500) : resp.body;
      debugPrint(
        '[Gemini] Error ${resp.statusCode} con modelo $modelId usando ${keyUsed == primary ? 'PRIMARY' : 'FALLBACK'}: $bodyPreview',
      );
      return AIResponse(text: 'Error al conectar con Gemini: \n$bodyPreview');
    }

    // Retornar respuesta de texto/visión (sin generación de imagen)
    return await sendToModel(selectedModel);
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
