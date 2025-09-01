import 'package:ai_chan/shared.dart';

class OpenAiTtsUtils {
  /// Devuelve la lista estática de voces OpenAI en el formato que usa el UI
  static List<Map<String, dynamic>> loadStaticOpenAiVoices() {
    return kOpenAIVoices
        .map((v) => {'name': v, 'description': v, 'languageCodes': <String>[]})
        .toList();
  }

  /// Formatea nombre y subtítulo legible para el UI.
  /// Subtítulo: 'Género · Multilingüe' (sin token)
  static Map<String, String> formatVoiceDisplay(Map<String, dynamic> voice) {
    final token = (voice['name'] as String? ?? '').trim();
    String displayName = token;
    if (token.isNotEmpty) {
      displayName = '${token[0].toUpperCase()}${token.substring(1)}';
    }

    final genderLabel = (kOpenAIVoiceGender[token.toLowerCase()] ?? '')
        .toString();
    final genderPart = genderLabel.isNotEmpty ? genderLabel : '';
    final parts = <String>[];
    if (genderPart.isNotEmpty) parts.add(genderPart);
    parts.add('Multilingüe');
    final subtitle = parts.join(' · ');

    return {'displayName': displayName, 'subtitle': subtitle};
  }
}
