import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:ai_chan/core/config.dart';

class AIChatResult {
  final String text;
  final bool isImage;
  final String? imagePath;
  final String? prompt;
  final String? seed;
  final String finalModelUsed;
  AIChatResult({
    required this.text,
    required this.isImage,
    required this.imagePath,
    required this.prompt,
    required this.seed,
    required this.finalModelUsed,
  });
}

/// Servicio que encapsula la lógica de enviar mensaje a la IA (incluye reintentos,
/// detección de generación de imagen y guardado de base64 a fichero).
class AiChatResponseService {
  static final RegExp _imageGenPattern = RegExp(
    r'tools.*(image_generation|Image Generation)',
    caseSensitive: false,
  );
  static final RegExp _markdownImagePattern = RegExp(
    r'!\[.*?\]\((https?:\/\/.*?)\)',
  );
  static final RegExp _urlInTextPattern = RegExp(
    r'https?:\/\/\S+\.(jpg|jpeg|png|webp|gif)',
  );

  static int _extractWaitSeconds(String text) {
    final regex = RegExp(r'try again in ([\d\.]+)s');
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount > 0) {
      return double.tryParse(match.group(1) ?? '8')?.round() ?? 8;
    }
    return 8;
  }

  static bool _hasValidText(AIResponse r) {
    final t = r.text.trim();
    if (t.isEmpty) return r.base64.isNotEmpty; // permitir solo imagen
    final lower = t.toLowerCase();
    if (lower.contains('error al conectar con la ia')) return false;
    if (lower.contains('"error"')) return false;
    return true;
  }

  // Validación estricta de etiquetas permitidas.
  // Reglas:
  //  - Etiquetas permitidas: [audio]...[/audio], [img_caption]...[/img_caption], [call][/call], [end_call][/end_call]
  //  - [call][/call] y [end_call][/end_call] deben ser el ÚNICO contenido (ignorando espacios) del mensaje y estar vacías dentro.
  //  - [audio] debe tener contenido no vacío que no contenga otra etiqueta de apertura '[' inmediatamente (evitar nesting).
  //  - [img_caption] si aparece debe ir antes que cualquier otro texto (tras recorte inicial) y solo 1 vez.
  //  - Cualquier secuencia estilo [palabra] o [/palabra] distinta a las permitidas => inválido.
  //  - Secuencias de rol dentro de corchetes con espacios internos (ej: [y ahora alberto te envia flores]) NO se consideran etiquetas y se ignoran.
  static bool _hasValidAllowedTagsStructure(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;

    final tagToken = RegExp(r'\[/?([a-zA-Z0-9_]+)\]');
    final matches = tagToken.allMatches(trimmed).toList();
    // Extraer tokens detectados (solo los que no llevan espacios dentro, para no confundir roleplay)
    final allowed = {'audio', 'img_caption', 'call', 'end_call'};
    final tokens = <String>[];
    for (final m in matches) {
      final name = m.group(1);
      if (name == null) continue;
      tokens.add(name.toLowerCase());
    }
    // Buscar tokens inventados
    for (final tk in tokens) {
      if (!allowed.contains(tk)) {
        return false; // etiqueta inventada
      }
    }

    // Validación de [call][/call] y [end_call][/end_call]
    if (trimmed.contains('[call]') || trimmed.contains('[end_call]')) {
      final simpleTagPattern = RegExp(
        r'^\s*(\[(?:call|end_call)\]\s*\[/(?:call|end_call)\])\s*$',
      );
      if (!simpleTagPattern.hasMatch(trimmed)) {
        return false; // Debe ser lo único
      }
      // Nada más que validar en este caso
      return true;
    }

    // Validación de img_caption: si existe, debe ir al inicio
    final imgCaptionOpen = '[img_caption]';
    final imgCaptionClose = '[/img_caption]';
    if (trimmed.contains(imgCaptionOpen)) {
      final firstIdx = trimmed.indexOf(imgCaptionOpen);
      if (firstIdx != 0) return false; // Debe iniciar el mensaje
      final closeIdx = trimmed.indexOf(
        imgCaptionClose,
        firstIdx + imgCaptionOpen.length,
      );
      if (closeIdx < 0) return false; // falta cierre
      final after = trimmed
          .substring(closeIdx + imgCaptionClose.length)
          .trimLeft();
      // No permitir segunda aparición
      if (after.contains(imgCaptionOpen)) return false;
    }

    // Validación de audio tags (puede haber 0 o 1)
    final audioOpen = '[audio]';
    final audioClose = '[/audio]';
    if (trimmed.contains(audioOpen)) {
      final openIdx = trimmed.indexOf(audioOpen);
      final closeIdx = trimmed.indexOf(audioClose, openIdx + audioOpen.length);
      if (closeIdx < 0) return false; // Falta cierre
      final inner = trimmed
          .substring(openIdx + audioOpen.length, closeIdx)
          .trim();
      if (inner.isEmpty) return false; // Debe tener texto
      // Si inner empieza con '[' considerarlo intento de anidar etiqueta no permitida
      if (inner.startsWith('[')) return false;
      // Solo una pareja de audio
      final afterAudio = trimmed.substring(closeIdx + audioClose.length);
      if (afterAudio.contains(audioOpen)) return false;
    }

    // Validar que no existan cierres sin apertura o aperturas sin cierre
    // Conteos simples
    bool balanced(String name) {
      final openCount = RegExp('\\[$name\\]').allMatches(trimmed).length;
      final closeCount = RegExp('\\[/$name\\]').allMatches(trimmed).length;
      return openCount == closeCount;
    }

    for (final name in ['audio', 'img_caption']) {
      if (!balanced(name)) return false;
    }
    return true;
  }

  static Future<AIChatResult> send({
    required List<Message> recentMessages,
    required SystemPrompt systemPromptObj,
    required String model,
    String? imageBase64,
    String? imageMimeType,
    required bool enableImageGeneration,
    int maxRetries = 3,
  }) async {
    String selected = model;

    // Helper local para convertir Message -> history entry
    Map<String, String> toHistoryEntry(Message m) {
      String content = m.text.trim();
      final imgPrompt = m.image?.prompt?.trim() ?? '';
      if (imgPrompt.isNotEmpty) {
        final caption = '[img_caption]$imgPrompt[/img_caption]';
        content = content.isEmpty ? caption : '$caption\n\n$content';
      }
      final role = m.sender == MessageSender.user
          ? 'user'
          : m.sender == MessageSender.assistant
          ? 'ia'
          : m.sender == MessageSender.system
          ? 'system'
          : 'unknown';
      return {
        "role": role,
        "content": content,
        "datetime": m.dateTime.toIso8601String(),
      };
    }

    AIResponse response = await AIService.sendMessage(
      recentMessages.map(toHistoryEntry).toList(),
      systemPromptObj,
      model: selected,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    // Si la respuesta sugiere tool image_generation y no es GPT ni Gemini, reenviar forzando gpt-4.1-mini
    if (_imageGenPattern.hasMatch(response.text)) {
      final lower = selected.toLowerCase();
      final isGpt = lower.startsWith('gpt-');
      final isGemini = lower.startsWith('gemini-');
      if (!isGpt && !isGemini) {
        // Re-forward: requerir DEFAULT_IMAGE_MODEL configurado o fallar.
        final cfgModel = Config.requireDefaultImageModel();
        selected = cfgModel;
        response = await AIService.sendMessage(
          recentMessages.map(toHistoryEntry).toList(),
          systemPromptObj,
          model: selected,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          enableImageGeneration: true,
        );
      }
    }

    int retry = 0;
    while ((!_hasValidText(response) ||
            !_hasValidAllowedTagsStructure(response.text)) &&
        retry < maxRetries) {
      final waitSeconds = _extractWaitSeconds(response.text);
      await Future.delayed(Duration(seconds: waitSeconds));
      response = await AIService.sendMessage(
        recentMessages.map(toHistoryEntry).toList(),
        systemPromptObj,
        model: selected,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
      retry++;
    }

    if (!_hasValidText(response) ||
        !_hasValidAllowedTagsStructure(response.text)) {
      // Último intento inválido: sanitizar removiendo etiquetas desconocidas para no mostrar markup roto.
      String sanitized = response.text;
      // Quitar cualquier tag desconocido tipo [xxxx] o [/xxxx] que no sea permitido
      sanitized = sanitized.replaceAll(
        RegExp(r'\[(?!/?(?:audio|img_caption|call|end_call)\b)[^\]\[]+\]'),
        '',
      );
      return AIChatResult(
        text: sanitized,
        isImage: false,
        imagePath: null,
        prompt: response.prompt,
        seed: response.seed,
        finalModelUsed: selected,
      );
    }
    // Estructura válida: si es [call][/call] o [end_call][/end_call] dejarlo tal cual (ChatBubble lo gestionará).
    final trimmed = response.text.trim();
    if (trimmed.startsWith('[call]') || trimmed.startsWith('[end_call]')) {
      // Normalizar a formato exacto
      final exactPattern = RegExp(r'^\s*\[(call|end_call)\]\s*\[/\1\]\s*$');
      if (!exactPattern.hasMatch(trimmed)) {
        final kindMatch = RegExp(r'\[(call|end_call)\]').firstMatch(trimmed);
        final kind = kindMatch != null ? kindMatch.group(1) : 'call';
        response = AIResponse(
          text: '[$kind][/$kind]',
          base64: response.base64,
          seed: response.seed,
          prompt: response.prompt,
        );
      }
    }

    bool isImageResp = response.base64.isNotEmpty;
    String? imagePathResp;
    String textResponse = response.text;

    if (isImageResp) {
      // Validar que realmente sea base64 y no una URL
      final urlPattern = RegExp(r'^(https?:\/\/|file:|\/|[A-Za-z]:\\)');
      if (urlPattern.hasMatch(response.base64)) {
        Log.e(
          'La IA envió una URL/ruta en vez de imagen base64',
          tag: 'AI_CHAT_RESPONSE',
        );
        textResponse +=
            '\n[ERROR: La IA envió una URL/ruta en vez de imagen. Pide la foto de nuevo.]';
        isImageResp = false;
      } else {
        try {
          imagePathResp = await saveBase64ImageToFile(
            response.base64,
            prefix: 'img',
          );
          if (imagePathResp == null) {
            Log.e(
              'No se pudo guardar la imagen localmente',
              tag: 'AI_CHAT_RESPONSE',
            );
            isImageResp = false;
          }
        } catch (e) {
          Log.e('Fallo guardando imagen', tag: 'AI_CHAT_RESPONSE', error: e);
          isImageResp = false;
          imagePathResp = null;
        }
      }
    }

    if (_markdownImagePattern.hasMatch(textResponse) ||
        _urlInTextPattern.hasMatch(textResponse)) {
      Log.e(
        'La IA envió una imagen Markdown o URL en el texto',
        tag: 'AI_CHAT_RESPONSE',
      );
      textResponse +=
          '\n[ERROR: La IA envió una imagen como enlace o Markdown. Pide la foto de nuevo.]';
    }

    return AIChatResult(
      text: textResponse,
      isImage: isImageResp,
      imagePath: imagePathResp,
      prompt: response.prompt,
      seed: response.seed,
      finalModelUsed: selected,
    );
  }
}
