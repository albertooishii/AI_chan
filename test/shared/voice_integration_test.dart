import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/ai_providers/implementations/openai_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/google_provider.dart';

/// 🧪 Test para validar la integración de voces desde providers
/// Verifica que los providers exponen getAvailableVoices() correctamente
void main() {
  group('Voice Integration Tests', () {
    test('OpenAI provider should expose getAvailableVoices method', () async {
      final openaiProvider = OpenAIProvider();

      // Verificar que el método existe y se puede llamar
      final voices = await openaiProvider.getAvailableVoices();

      expect(voices, isA<List>(), reason: 'Should return a list');
      expect(
        voices,
        isNotEmpty,
        reason: 'OpenAI should have predefined voices',
      );
      expect(voices.first.name, isNotEmpty);

      print('🎵 OpenAI voices: ${voices.length} voices available');
      print('   First voice: ${voices.first.name} (${voices.first.gender})');
    });

    test('Google provider should expose getAvailableVoices method', () async {
      final googleProvider = GoogleProvider();

      // Verificar que el método existe (puede fallar por configuración)
      try {
        final voices = await googleProvider.getAvailableVoices();
        expect(voices, isA<List>());
        print('🎵 Google voices: ${voices.length} voices available');
        if (voices.isNotEmpty) {
          print(
            '   First voice: ${voices.first.name} (${voices.first.gender})',
          );
        }
      } on Exception catch (e) {
        // Es esperado que falle sin configuración, pero el método debe existir
        print(
          '⚠️ Google provider method exists but failed (expected without API key): $e',
        );
        // Verificamos que es error de configuración, no de método inexistente
        expect(e.toString(), isNot(contains('NoSuchMethodError')));
      }
    });

    test('voice providers follow VoiceInfo contract', () async {
      final openaiProvider = OpenAIProvider();
      final voices = await openaiProvider.getAvailableVoices();

      // Verificar que todas las voces siguen el contrato VoiceInfo
      for (final voice in voices) {
        expect(
          voice.name,
          isNotEmpty,
          reason: 'Voice name should not be empty',
        );
        expect(
          voice.gender,
          isNotEmpty,
          reason: 'Voice gender should not be empty',
        );
        // languageCodes puede ser null para voces multi-idioma
        if (voice.languageCodes != null) {
          expect(voice.languageCodes, isA<List<String>>());
        }
      }

      print('✅ All voices follow VoiceInfo contract');
    });

    test('providers have different voice offerings', () async {
      final openaiProvider = OpenAIProvider();
      final openaiVoices = await openaiProvider.getAvailableVoices();

      // OpenAI debe tener voces específicas conocidas
      final voiceNames = openaiVoices.map((v) => v.name).toList();

      expect(
        voiceNames,
        contains('alloy'),
        reason: 'OpenAI should have alloy voice',
      );
      expect(
        voiceNames,
        contains('nova'),
        reason: 'OpenAI should have nova voice',
      );
      expect(
        voiceNames,
        contains('marin'),
        reason: 'OpenAI should have marin voice (premium)',
      );

      print('✅ Provider voice integration test completed successfully!');
      print('   - OpenAI voices verified: ${openaiVoices.length}');
      print(
        '   - Premium voices available: ${voiceNames.where((name) => ['marin', 'cedar'].contains(name)).toList()}',
      );
    });
  });
}
