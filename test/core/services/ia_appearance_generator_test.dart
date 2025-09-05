import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import '../../fakes/fake_ai_service.dart';
import 'package:ai_chan/core/models.dart';

void main() {
  test(
    'generateAppearanceFromBiography parses JSON and forces edad_aparente=25',
    () async {
      // Respuesta simulada que incluye un bloque JSON válido
      final jsonText =
          '{"edad_aparente": 30, "genero": "femenino", "conjuntos_ropa": []}';
      final resp = AIResponse(text: jsonText);
      final fake = FakeAIService.withResponses([resp]);
      AIService.testOverride = fake;

      final gen = IAAppearanceGenerator();
      final profile = AiChanProfile(
        biography: <String, dynamic>{'text': 'Le gusta bailar'},
        userName: 'u',
        aiName: 'a',
        userBirthdate: null,
        aiBirthdate: null,
        appearance: <String, dynamic>{},
        timeline: [],
      );
      final map = await gen.generateAppearanceFromBiography(profile);
      expect(map, isNotNull);
      expect(map['edad_aparente'], 25);
      expect(map['genero'], 'femenino');

      AIService.testOverride = null;
    },
  );
}
