import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

/// Servicio para generar resúmenes de llamadas de voz
class VoiceCallSummaryService {
  final AiChanProfile profile;

  VoiceCallSummaryService({required this.profile});

  /// Genera un resumen de texto simple para llamadas de voz
  Future<String> summarizeVoiceCall(
    List<Map<String, dynamic>> voiceMessages,
  ) async {
    if (voiceMessages.isEmpty) return '';

    try {
      final instrucciones =
          '''
Eres un analista de llamadas y debes producir un resumen breve EN ESPAÑOL SOLO cuando exista contenido con significado.

CUÁNDO RESUMIR (produce 2‑4 oraciones naturales):
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
• 2‑4 oraciones fluidas en español neutro.
• Usa SIEMPRE los nombres reales: usuario = ${profile.userName.trim()}, IA = ${profile.aiName.trim()}.
• Incluye: (a) tema(s) central(es); (b) acuerdos/decisiones o próxima acción; (c) tono emocional si es relevante.
• No enumeres con viñetas, no uses encabezados, no cites textualmente salvo que una frase sea esencial.
• No inventes detalles; si algo solo se insinuó, usa formulaciones prudentes ("se comentó la posibilidad de...").

FORMATO DE SALIDA:
• Únicamente el texto del resumen O la cadena exacta "SIN_CONTENIDO".
• No añadas prefijos, etiquetas, JSON ni markdown.
''';

      final response = await AIService.sendMessage(
        [],
        SystemPrompt(
          profile: profile,
          dateTime: DateTime.now(),
          recentMessages: voiceMessages,
          instructions: {'raw': instrucciones},
        ),
        // Usar el modelo configurado en .env en lugar de hardcodeado
      );

      final summaryText = response.text.trim();

      // Si la IA dijo SIN_CONTENIDO o devolvió vacío => no guardar
      if (summaryText == 'SIN_CONTENIDO' || summaryText.isEmpty) {
        return '';
      }
      return summaryText;
    } catch (e) {
      // Fallback más inteligente - analizar si hay contenido útil
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
          basicPhrases.any((phrase) => combinedContent.contains(phrase)) &&
          combinedContent.length < 50;

      if (hasOnlyBasicContent) {
        return ''; // Solo contenido básico, no guardar
      }

      // Si llegamos aquí, hay contenido suficiente para resumir
      if (userContent.isNotEmpty && aiContent.isNotEmpty) {
        return '${profile.userName} y ${profile.aiName} conversaron durante la llamada.';
      } else if (userContent.isNotEmpty) {
        return '${profile.userName} habló durante la llamada.';
      } else if (aiContent.isNotEmpty) {
        return '${profile.aiName} respondió durante la llamada.';
      }

      return ''; // Fallback final - no guardar
    }
  }

  /// Genera un resumen de texto natural usando el método dedicado
  Future<String> generateSummaryText(VoiceCallSummary callSummary) async {
    if (callSummary.messages.isEmpty) return '';

    try {
      // Convertir VoiceCallMessage a formato compatible
      final voiceMessages = callSummary.messages.map((voiceMsg) {
        final role = voiceMsg.isUser ? 'user' : 'assistant';
        return {
          'role': role,
          'content': voiceMsg.text.trim(),
          'datetime': voiceMsg.timestamp.toIso8601String(),
        };
      }).toList();

      // Usar el método propio del servicio
      final summary = await summarizeVoiceCall(voiceMessages);

      // Si no hay resumen (cadena vacía), no crear mensaje
      if (summary.isEmpty) {
        return '';
      }

      // Envolver el resumen en etiquetas [call] para ocultarlo en el bubble
      return '[call]$summary[/call]';
    } catch (e) {
      // Fallback más inteligente - también puede devolver cadena vacía
      final userMessages = callSummary.messages.where((m) => m.isUser).toList();
      final aiMessages = callSummary.messages.where((m) => !m.isUser).toList();

      final userTexts = userMessages
          .map((m) => m.text.trim())
          .where((t) => t.isNotEmpty)
          .join(' ');
      final aiTexts = aiMessages
          .map((m) => m.text.trim())
          .where((t) => t.isNotEmpty)
          .join(' ');

      // Si no hay suficiente contenido, no guardar
      if (userTexts.length < 10 && aiTexts.length < 20) {
        return '';
      }

      // Crear fallback solo si hay contenido suficiente
      String fallbackText = '';
      if (userTexts.isNotEmpty && aiTexts.isNotEmpty) {
        fallbackText =
            '${profile.userName} y ${profile.aiName} conversaron durante la llamada.';
      } else if (userTexts.isNotEmpty) {
        fallbackText = '${profile.userName} habló durante la llamada.';
      } else if (aiTexts.isNotEmpty) {
        fallbackText = '${profile.aiName} respondió durante la llamada.';
      }

      if (fallbackText.isEmpty) {
        return '';
      }

      return '[call]$fallbackText[/call]';
    }
  }
}
