import '../models/message.dart';
import '../models/ai_chan_profile.dart';
import '../models/system_prompt.dart';
import 'ai_service.dart';

/// Servicio para generar resúmenes de llamadas de voz
class VoiceCallSummaryService {
  final AiChanProfile profile;

  VoiceCallSummaryService({required this.profile});

  /// Genera un resumen de texto simple para llamadas de voz
  Future<String> summarizeVoiceCall(List<Map<String, dynamic>> voiceMessages) async {
    if (voiceMessages.isEmpty) return '';

    try {
      final instrucciones =
          '''
Eres un asistente especializado en resumir llamadas de voz. Tu tarea es crear un resumen natural y fluido en español de la conversación telefónica SOLO si hubo contenido útil o significativo.

Si la llamada NO tuvo contenido útil (solo saludos, pruebas de audio, ruido, palabras sueltas sin sentido, o conversación muy breve sin sustancia), responde exactamente: "SIN_CONTENIDO"

Si SÍ hubo contenido útil, describe de forma clara y concisa:
• Los temas principales que se discutieron
• Las decisiones o acuerdos importantes
• El tono emocional de la conversación
• Cualquier plan o promesa mencionada

El resumen debe ser como si alguien te preguntara "¿de qué hablaron en la llamada?" - responde de forma natural en 2-4 oraciones.

Usa SIEMPRE los nombres reales: usuario = ${profile.userName.trim()}, IA = ${profile.aiName.trim()}.

Responde únicamente con el resumen en texto natural o "SIN_CONTENIDO", sin formato JSON ni estructura especial.
''';

      final response = await AIService.sendMessage(
        [],
        SystemPrompt(
          profile: profile,
          dateTime: DateTime.now(),
          recentMessages: voiceMessages,
          instructions: instrucciones,
        ),
        // Usar el modelo configurado en .env en lugar de hardcodeado
      );

      final summaryText = response.text.trim();

      // Si la IA determinó que no hay contenido útil, devolver cadena vacía
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
      final basicPhrases = ['hola', 'hello', 'test', 'prueba', 'audio', 'me escuchas', 'funciona'];
      final hasOnlyBasicContent =
          basicPhrases.any((phrase) => combinedContent.contains(phrase)) && combinedContent.length < 50;

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
        return {'role': role, 'content': voiceMsg.text.trim(), 'datetime': voiceMsg.timestamp.toIso8601String()};
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

      final userTexts = userMessages.map((m) => m.text.trim()).where((t) => t.isNotEmpty).join(' ');
      final aiTexts = aiMessages.map((m) => m.text.trim()).where((t) => t.isNotEmpty).join(' ');

      // Si no hay suficiente contenido, no guardar
      if (userTexts.length < 10 && aiTexts.length < 20) {
        return '';
      }

      // Crear fallback solo si hay contenido suficiente
      String fallbackText = '';
      if (userTexts.isNotEmpty && aiTexts.isNotEmpty) {
        fallbackText = '${profile.userName} y ${profile.aiName} conversaron durante la llamada.';
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
