import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/onboarding/services/conversational_onboarding_service.dart';

void main() {
  group('🔍 Validation Service Tests', () {
    test('should validate and save correct data successfully', () {
      // Datos válidos
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userName',
        'Alberto',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('Alberto'));
    });

    test('should reject empty country data', () {
      // País vacío - debe fallar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userCountry',
        '',
      );

      expect(result['isValid'], isFalse);
      expect(result['reason'], contains('País'));
    });

    test('should reject invalid date formats', () {
      // Fecha inválida - debe fallar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userBirthdate',
        'Por favor ayúdame a recordar.',
      );

      expect(result['isValid'], isFalse);
      expect(result['reason'], contains('fecha'));
    });

    test('should accept valid date formats', () {
      // Fecha válida en formato DD/MM/YYYY
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userBirthdate',
        '15/03/1990',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('15/03/1990'));
    });

    test('should accept valid country names', () {
      // País válido
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userCountry',
        'España',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('ES'));
    });

    test('should validate name with proper trimming', () {
      // Nombre con espacios - debe limpiar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userName',
        '  Alberto  ',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('Alberto'));
    });

    test('should accept AUTO_GENERATE_STORY flag for meet story', () {
      final result = ConversationalOnboardingService.validateAndSaveData(
        'meetStory',
        'AUTO_GENERATE_STORY',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('AUTO_GENERATE_STORY'));
    });

    test('should accept user provided meet story', () {
      final story =
          'Nos conocimos en una cafetería en Madrid, él se acercó y me ofreció un libro.';
      final result = ConversationalOnboardingService.validateAndSaveData(
        'meetStory',
        story,
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals(story));
    });

    test('should accept ai name and trim', () {
      final result = ConversationalOnboardingService.validateAndSaveData(
        'aiName',
        'Yuna',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('Yuna'));
    });

    test('should accept ai country value', () {
      final result = ConversationalOnboardingService.validateAndSaveData(
        'aiCountry',
        'JP',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('JP'));
    });

    test('should reject empty or whitespace-only names', () {
      // Nombre vacío - debe fallar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'userName',
        '   ',
      );

      expect(result['isValid'], isFalse);
      expect(result['reason'], contains('Nombre'));
    });

    group('Date Format Validation', () {
      test('should accept DD/MM/YYYY format', () {
        final result = ConversationalOnboardingService.validateAndSaveData(
          'userBirthdate',
          '25/12/1995',
        );

        expect(result['isValid'], isTrue);
      });

      test(
        'should reject natural language date (requires DD/MM/YYYY format)',
        () {
          final result = ConversationalOnboardingService.validateAndSaveData(
            'userBirthdate',
            'Nací el 25 de diciembre de 1995',
          );

          expect(result['isValid'], isFalse);
        },
      );

      test('should reject non-date text', () {
        final result = ConversationalOnboardingService.validateAndSaveData(
          'userBirthdate',
          'No recuerdo exactamente',
        );

        expect(result['isValid'], isFalse);
      });
    });
  });
}
