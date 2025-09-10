import 'package:ai_chan/shared/domain/interfaces/i_ai_service.dart';
import 'package:ai_chan/core/models.dart';

/// Servicio para generar resúmenes de llamadas de voz
class CallSummaryService {
  CallSummaryService({required this.profile, required this.aiService});

  final Map<String, dynamic> profile;
  final IAIService aiService;
  String _prepareConversationContent(
    final List<Map<String, dynamic>> voiceMessages,
  ) {
    final buffer = StringBuffer();

    for (final message in voiceMessages) {
      final role = message['role']?.toString() ?? 'unknown';
      final content = message['content']?.toString().trim() ?? '';

      if (content.isNotEmpty) {
        final speaker = role == 'user'
            ? (profile['userName']?.toString() ?? 'Usuario')
            : (profile['aiName']?.toString() ?? 'IA');
        buffer.writeln('$speaker: $content');
      }
    }

    return buffer.toString().trim();
  }

  /// Obtiene las instrucciones para generar el resumen
  String _getSummaryInstructions() {
    final userName = profile['userName']?.toString() ?? 'Usuario';
    final aiName = profile['aiName']?.toString() ?? 'IA';

    return '''
Eres un analista de llamadas y debes producir un resumen breve EN ESPAÑOL SOLO cuando exista contenido con significado.

CUÁNDO RESUMIR (produce 2-4 oraciones naturales):
Debe cumplirse AL MENOS UNO:
1. Se abordó un tema, problema, duda, idea, plan o decisión (más allá de saludo/prueba).
2. Hubo intercambio con al menos 2 turnos del usuario que aportan nueva información (no solo "hola", "¿me oyes?", "probando").
3. Se expresaron emociones u opiniones (ej: preocupación, interés, agrado, frustración) relacionadas con algo concreto.
4. Se pactó o insinuó una acción futura, próxima consulta, tarea, recordatorio, seguimiento o compromiso.

CUÁNDO NO RESUMIR (responde EXACTAMENTE "SIN_CONTENIDO"):
• Solo saludos iniciales / despedidas.
• Solo pruebas de audio: "hola", "probando", "¿me escuchas?", "funciona", ecos, ruidos.
• Palabras sueltas o frases inconexas sin un tema claro.
• Duración efectiva con habla significativa < 5 segundos de contenido útil.

ESTILO DEL RESUMEN (cuando procede):
• 2-4 oraciones fluidas en español neutro.
• Usa SIEMPRE los nombres reales: usuario = $userName, IA = $aiName.
• Incluye: (a) tema(s) central(es); (b) acuerdos/decisiones o próxima acción; (c) tono emocional si es relevante.
• No enumeres con viñetas, no uses encabezados, no cites textualmente salvo que una frase sea esencial.
• No inventes detalles; si algo solo se insinuó, usa formulaciones prudentes ("se comentó la posibilidad de...").

FORMATO DE SALIDA:
• Únicamente el texto del resumen O la cadena exacta "SIN_CONTENIDO".
• No añadas prefijos, etiquetas, JSON ni markdown.
''';
  }

  /// Genera un resumen de texto simple para llamadas de voz
  Future<String> summarizeCall(
    final List<Map<String, dynamic>> voiceMessages,
  ) async {
    if (voiceMessages.isEmpty) return '';

    try {
      // Preparar el contenido de la conversación
      final conversationContent = _prepareConversationContent(voiceMessages);

      // Si no hay contenido suficiente, devolver vacío
      if (conversationContent.isEmpty) return '';

      // Preparar las instrucciones para la IA
      final instrucciones = _getSummaryInstructions();

      // Preparar el mensaje para la IA
      final messages = [
        {'role': 'system', 'content': instrucciones},
        {
          'role': 'user',
          'content':
              'Analiza esta conversación de llamada de voz y genera un resumen:\n\n$conversationContent',
        },
      ];

      // Enviar a la IA para generar el resumen usando nueva interface
      // Create a basic SystemPrompt for summary generation
      final dummyProfile = AiChanProfile(
        userName: profile['userName']?.toString() ?? 'Usuario',
        aiName: profile['aiName']?.toString() ?? 'IA',
        userBirthdate: null,
        aiBirthdate: null,
        biography: const <String, dynamic>{},
        appearance: const <String, dynamic>{},
      );

      final systemPrompt = SystemPrompt(
        profile: dummyProfile,
        dateTime: DateTime.now(),
        instructions: {
          'task': 'call_summary',
          'instructions': _getSummaryInstructions(),
        },
      );

      final history = messages
          .map((final m) => m.cast<String, String>())
          .toList();

      final response = await aiService.sendMessage(
        history,
        systemPrompt,
        model: 'gpt-4o-mini', // Default model for summaries
      );

      // Extraer el resumen de la respuesta
      final summaryText = response.text.trim();

      // Si la IA dijo SIN_CONTENIDO o devolvió vacío => no guardar
      if (summaryText == 'SIN_CONTENIDO' || summaryText.isEmpty) {
        return '';
      }

      return summaryText;
    } on Exception {
      // Fallback más inteligente - analizar si hay contenido útil
      return _generateFallbackSummary(voiceMessages);
    }
  }

  String _generateFallbackSummary(
    final List<Map<String, dynamic>> voiceMessages,
  ) {
    final userTexts = <String>[];
    final aiTexts = <String>[];

    for (final msg in voiceMessages) {
      final content = msg['content']?.toString().trim() ?? '';
      if (content.isNotEmpty) {
        if (msg['role'] == 'user') {
          userTexts.add(content);
        } else if (msg['role'] == 'assistant') {
          aiTexts.add(content);
        }
      }
    }

    final userContent = userTexts.join(' ').trim();
    final aiContent = aiTexts.join(' ').trim();

    // Si no hay contenido de usuario o es muy corto, no guardar
    if (userContent.length < 10 && aiContent.length < 20) {
      return ''; // No hay suficiente contenido útil
    }

    // Si solo hay contenido muy básico (saludos, pruebas), no guardar
    final combinedContent = '$userContent $aiContent'.toLowerCase();
    final basicPhrases = [
      'hola',
      'hello',
      'test',
      'prueba',
      'audio',
      'me escuchas',
      'funciona',
    ];
    final hasOnlyBasicContent =
        basicPhrases.any((final phrase) => combinedContent.contains(phrase)) &&
        combinedContent.length < 50;

    if (hasOnlyBasicContent) {
      return ''; // Solo contenido básico, no guardar
    }

    // Si llegamos aquí, hay contenido suficiente para resumir
    final userName = profile['userName']?.toString() ?? 'Usuario';
    final aiName = profile['aiName']?.toString() ?? 'IA';

    if (userContent.isNotEmpty && aiContent.isNotEmpty) {
      return '$userName y $aiName conversaron durante la llamada.';
    } else if (userContent.isNotEmpty) {
      return '$userName habló durante la llamada.';
    } else if (aiContent.isNotEmpty) {
      return '$aiName respondió durante la llamada.';
    }

    return ''; // Fallback final - no guardar
  }

  /// Genera un resumen de texto natural usando el método dedicado
  Future<String> generateSummaryText(
    final Map<String, dynamic> callSummary,
  ) async {
    final messages = callSummary['messages'] as List<dynamic>? ?? [];
    if (messages.isEmpty) return '';

    try {
      // Convertir mensajes a formato compatible
      final voiceMessages = messages.map((final voiceMsg) {
        final role =
            (voiceMsg as Map<String, dynamic>)['isUser'] as bool? ?? false
            ? 'user'
            : 'assistant';
        return {
          'role': role,
          'content': (voiceMsg['text'] as String?)?.trim() ?? '',
          'datetime':
              (voiceMsg['timestamp'] as DateTime?)?.toIso8601String() ??
              DateTime.now().toIso8601String(),
        };
      }).toList();

      // Usar el método propio del servicio
      final summary = await summarizeCall(voiceMessages);

      // Si no hay resumen (cadena vacía), no crear mensaje
      if (summary.isEmpty) {
        return '';
      }

      // Envolver el resumen en etiquetas [call] para ocultarlo en el bubble
      return '[call]$summary[/call]';
    } on Exception {
      // Fallback más inteligente - también puede devolver cadena vacía
      return _generateFallbackSummary(
        messages.map((final voiceMsg) {
          final msg = voiceMsg as Map<String, dynamic>;
          final role = msg['isUser'] as bool? ?? false ? 'user' : 'assistant';
          return {
            'role': role,
            'content': (msg['text'] as String?)?.trim() ?? '',
          };
        }).toList(),
      );
    }
  }
}
