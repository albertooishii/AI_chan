import 'package:ai_chan/core/cache/cache_service.dart';
import 'package:ai_chan/core/config.dart';
import 'dart:convert';
import '../utils/log_utils.dart';
import 'dart:async';
import 'dart:io';
import '../utils/audio_utils.dart';
import 'package:ai_chan/shared/utils/audio_conversion.dart';

import 'ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/prompt_builder.dart';
import 'package:http/http.dart' as http;
import 'package:ai_chan/core/http_connector.dart';

class OpenAIService implements AIService {
  /// Obtiene la lista de modelos disponibles en la API de OpenAI, ordenados por fecha de creación (más nuevo primero)
  @override
  Future<List<String>> getAvailableModels() async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    const endpoint = 'https://api.openai.com/v1/models';
    final response = await HttpConnector.client.get(
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
      Log.d('Listado de modelos GPT ordenados:', tag: 'OPENAI_SERVICE');
      for (final model in ordered) {
        Log.d(model, tag: 'OPENAI_SERVICE');
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
    // Safety: refuse to call OpenAI endpoints with non-OpenAI model ids.
    final modelNorm = model?.trim().toLowerCase() ?? '';
    if (modelNorm.isNotEmpty && !modelNorm.startsWith('gpt-')) {
      Log.e('OpenAIService called with non-OpenAI model "$model". Aborting remote call.', tag: 'OPENAI_SERVICE');
      return AIResponse(
        text:
            'Error: modelo no válido para OpenAI: $model. Asegúrate de usar un modelo que empiece por "gpt-" o de enrutar la petición al proveedor correcto.',
      );
    }
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
    final systemPromptMap = systemPrompt.toJson();
    // Detectar si la petición es explícitamente para generar un AVATAR.
    bool looksLikeAvatar = false;
    try {
      final instrDetect = systemPromptMap['instructions'];
      if (instrDetect is Map) {
        if (instrDetect['is_avatar'] == true) {
          looksLikeAvatar = true;
        }
      }
    } catch (_) {}

    // Garantizar que las instrucciones de AVATAR y las de FOTO/Metadatos no se mezclen.
    // Regla simple y explícita: si es una petición de avatar, eliminar cualquier clave
    // relacionada con imagen (p.ej. 'photo_instructions' / 'attached_image_metadata_instructions')
    // para evitar contaminación accidental. Si no es una petición de avatar,
    // inyectar las instrucciones de foto/metadatos cuando proceda y eliminar
    // claves específicas de avatar si estuvieran presentes.
    try {
      final instrRoot = systemPromptMap['instructions'];
      if (instrRoot is Map) {
        if (!looksLikeAvatar) {
          // Inyectar instrucciones sobre foto y metadatos cuando corresponda
          if (enableImageGeneration) {
            instrRoot['photo_instructions'] = imageInstructions(systemPrompt.profile.userName);
          }
          if (imageBase64 != null && imageBase64.isNotEmpty) {
            instrRoot['attached_image_metadata_instructions'] = imageMetadata(systemPrompt.profile.userName);
          }
        }
      }
    } catch (_) {}
    final systemPromptStr = jsonEncode(systemPromptMap);
    // El contenido del sistema proviene de PromptBuilder; las instrucciones específicas
    // sobre metadatos de imagen ([img_caption]) están definidas allí.
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
    // Prefer explicit getter firstAvatar for clarity (primer avatar histórico)
    final avatar = systemPrompt.profile.firstAvatar;
    // El bloque 'role: user' siempre primero
    input.add({"role": "user", "content": userContent});
    // Declarar tools vacío
    List<Map<String, dynamic>> tools = [];
    // Luego image_generation_call y tools si corresponde
    if (enableImageGeneration) {
      Log.i('image_generation ACTIVADO', tag: 'OPENAI_SERVICE');
      tools = [
        {"type": "image_generation", "input_fidelity": "high", "moderation": "low"},
      ];

      final imageGenCall = <String, dynamic>{"type": "image_generation_call"};
      // Incluir id si existe
      if (avatar != null && avatar.seed != null) {
        imageGenCall['id'] = avatar.seed;
        Log.d('Usando imageId: ${avatar.seed}', tag: 'OPENAI_SERVICE');
      }
      // Si es avatar explícito, forzar tamaño 1024x1024
      if (looksLikeAvatar) {
        imageGenCall['size'] = '1024x1024';
        Log.d('Detección: petición tratada como AVATAR -> size=1024x1024', tag: 'OPENAI_SERVICE');
      }
      input.add(imageGenCall);
    } else {
      Log.i('image_generation DESACTIVADO', tag: 'OPENAI_SERVICE');
    }
    int tokens = estimateTokens(history, systemPrompt);
    if (tokens > 128000) {
      return AIResponse(
        text:
            'Error: El mensaje supera el límite de 128,000 tokens permitido por GPT-5 y GPT-4o. Reduce la cantidad de mensajes o bloques.',
      );
    }
    final Map<String, dynamic> bodyMap = {
      "model": model ?? Config.getDefaultImageModel(), // default OpenAI cuando se fuerza imagen
      "input": input,
      if (tools.isNotEmpty) "tools": tools,
      // Nota: No incluir 'modalities' aquí; algunos modelos del endpoint /responses no lo soportan
    };
    final body = jsonEncode(bodyMap);

    final response = await HttpConnector.client.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
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
              if (img['data'] is String && (img['data'] as String).startsWith('data:image/')) {
                return img['data'];
              }
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
            if (item['result'] != null && imageBase64.isEmpty) {
              imageBase64 = item['result'];
            }
            if (item['id'] != null && imageId.isEmpty) imageId = item['id'];
            if (item['revised_prompt'] != null && revisedPrompt.isEmpty) {
              revisedPrompt = item['revised_prompt'];
            }
            if (text.trim().isEmpty && item['text'] != null) {
              text = item['text'];
            }
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
      // NOTE: La extracción de [img_caption] se realiza centralmente en AIService.sendMessage

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
      Log.e('ERROR: statusCode=${response.statusCode}, body=${response.body}', tag: 'OPENAI_SERVICE');
      return AIResponse(text: 'Error al conectar con la IA: Status ${response.statusCode} ${response.body}');
    }
  }

  String get apiKey => Config.getOpenAIKey();

  /// Transcribe un archivo de audio usando OpenAI Whisper
  Future<String?> transcribeAudio(String filePath, {String? language, Map<String, String>? extraFields}) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = Config.getOpenAISttModel()
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    if (language != null && language.trim().isNotEmpty) {
      request.fields['language'] = language.trim();
    }

    // Añadir cualquier campo extra permitido por la API (p.ej. prompt, response_format)
    if (extraFields != null) {
      extraFields.forEach((k, v) {
        try {
          request.fields[k] = v;
        } catch (_) {}
      });
    }

    try {
      final streamed = await (HttpConnector.client)
          .send(request)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Timeout en transcripción de audio', const Duration(seconds: 30)),
          );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] as String?;
      } else {
        throw Exception('Error STT OpenAI (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Timeout al transcribir audio: la conexión tardó demasiado');
      } else if (e.toString().contains('Connection closed') || e.toString().contains('ClientException')) {
        throw Exception('Error de conexión al transcribir audio: verifica tu conexión a internet');
      } else {
        throw Exception('Error STT OpenAI: $e');
      }
    }
  }

  /// Genera un archivo de voz usando OpenAI TTS con caché
  Future<File?> textToSpeech({required String text, String voice = 'sage', String? model, String? outputDir}) async {
    Log.d('textToSpeech called - text: "${text.length} chars", voice: $voice, model: $model', tag: 'OPENAI_TTS');

    if (apiKey.trim().isEmpty) {
      Log.e('Missing OpenAI API key', tag: 'OPENAI_TTS');
      throw Exception('Falta la API key de OpenAI. Por favor, configúrala en la app.');
    }
    if (text.trim().isEmpty) {
      Log.w('Empty text provided', tag: 'OPENAI_TTS');
      return null;
    }

    try {
      // Verificar caché primero
      // Preferir caché solo para demo/dialog TTS — los audios de mensajes se
      // guardan en el directorio tradicional configurado por AUDIO_DIR.
      final effectiveModel = model ?? Config.getOpenAITtsModel();

      final cachedFile = await CacheService.getCachedAudioFile(
        text: text,
        voice: voice,
        languageCode: 'openai-$effectiveModel', // Usar modelo como "idioma" para OpenAI
        provider: 'openai',
        extension: 'mp3',
      );

      if (cachedFile != null) {
        Log.d('Usando audio desde caché', tag: 'OPENAI_TTS');
        return cachedFile;
      }
    } catch (e) {
      Log.w('Error leyendo caché, continuando con API: $e', tag: 'OPENAI_TTS');
    }

    final effectiveModel = model ?? Config.getOpenAITtsModel();

    final url = Uri.parse('https://api.openai.com/v1/audio/speech');
    final response = await HttpConnector.client.post(
      url,
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({'model': effectiveModel, 'input': text, 'voice': voice, 'response_format': 'mp3'}),
    );

    if (response.statusCode == 200) {
      try {
        // Guardar en caché primero
        // Intentar guardar en caché (esto ayuda al diálogo TTS), pero si
        // falla, persistir en el directorio de audios normal.
        try {
          // Respect configured preferred audio format when saving/caching.
          final preferredRaw = Config.get('PREFERRED_AUDIO_FORMAT', 'mp3');
          final preferred = preferredRaw.trim().toLowerCase();
          String ext = preferred == 'm4a' ? 'm4a' : 'mp3';
          var dataToSave = response.bodyBytes;
          try {
            final converted = await AudioConversion.convertBytesToPreferredCompressed(dataToSave, preferred);
            if (converted != null && converted.isNotEmpty) {
              dataToSave = converted;
            }
          } catch (e) {
            Log.w('Warning: Could not convert OpenAI TTS to preferred format: $e', tag: 'OPENAI_TTS');
          }

          final cachedFile = await CacheService.saveAudioToCache(
            audioData: dataToSave,
            text: text,
            voice: voice,
            languageCode: 'openai-$model',
            provider: 'openai',
            extension: ext,
          );

          if (cachedFile != null) {
            Log.d('Audio guardado en caché y devuelto', tag: 'OPENAI_TTS');
            return cachedFile;
          }
        } catch (e) {
          Log.w('Warning: Error guardando en caché: $e', tag: 'OPENAI_TTS');
        }
      } catch (e) {
        Log.w('Warning: Error guardando en caché: $e', tag: 'OPENAI_TTS');
      }

      // Fallback: guardar en directorio tradicional si el caché falla
      String dirPath;
      if (outputDir != null && outputDir.trim().isNotEmpty) {
        dirPath = outputDir;
      } else {
        final audioDir = await getLocalAudioDir();
        dirPath = audioDir.path;
      }
      final file = File('$dirPath/ai_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      if (!await File(dirPath).exists()) {
        await Directory(dirPath).create(recursive: true);
      }
      await file.writeAsBytes(response.bodyBytes);
      Log.i('Audio generado sin caché: ${file.path}', tag: 'OPENAI_TTS');
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

  /// Obtiene la lista de voces disponibles de OpenAI (estática, no requiere API)
  static List<Map<String, dynamic>> getAvailableVoices() {
    return [
      {
        'name': 'alloy',
        'description': 'Alloy - Voz equilibrada y versátil',
        'gender': 'neutral',
        'language': 'multi',
        'provider': 'openai',
      },
      {
        'name': 'echo',
        'description': 'Echo - Voz clara y directa',
        'gender': 'neutral',
        'language': 'multi',
        'provider': 'openai',
      },
      {
        'name': 'fable',
        'description': 'Fable - Voz narrativa y expresiva',
        'gender': 'neutral',
        'language': 'multi',
        'provider': 'openai',
      },
      {
        'name': 'onyx',
        'description': 'Onyx - Voz profunda y autoritative',
        'gender': 'masculine',
        'language': 'multi',
        'provider': 'openai',
      },
      {
        'name': 'nova',
        'description': 'Nova - Voz joven y enérgica',
        'gender': 'feminine',
        'language': 'multi',
        'provider': 'openai',
      },
      {
        'name': 'shimmer',
        'description': 'Shimmer - Voz suave y cálida',
        'gender': 'feminine',
        'language': 'multi',
        'provider': 'openai',
      },
    ];
  }

  /// Obtiene voces femeninas de OpenAI
  static List<Map<String, dynamic>> getFemaleVoices() {
    return getAvailableVoices().where((voice) => voice['gender'] == 'feminine').toList();
  }

  /// Limpia el caché de audio de OpenAI
  static Future<void> clearAudioCache() async {
    try {
      await CacheService.clearAudioCache();
      Log.i('Caché de audio limpiado', tag: 'OPENAI_TTS');
    } catch (e) {
      Log.w('Error limpiando caché de audio: $e', tag: 'OPENAI_TTS');
    }
  }
}
