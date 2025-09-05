import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/onboarding/services/conversational_onboarding_service.dart';

void main() {
  group('🔍 Validation Service Tests', () {
    test('should validate and save correct data successfully', () {
      // Datos válidos
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingName',
        'Alberto',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('Alberto'));
    });

    test('should reject empty country data', () {
      // País vacío - debe fallar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingCountry',
        '',
      );

      expect(result['isValid'], isFalse);
      expect(result['reason'], contains('País'));
    });

    test('should reject invalid date formats', () {
      // Fecha inválida - debe fallar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingBirthdate',
        'Por favor ayúdame a recordar.',
      );

      expect(result['isValid'], isFalse);
      expect(result['reason'], contains('fecha'));
    });

    test('should accept valid date formats', () {
      // Fecha válida en formato DD/MM/YYYY
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingBirthdate',
        '15/03/1990',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('15/03/1990'));
    });

    test('should accept valid country names', () {
      // País válido
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingCountry',
        'España',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('España'));
    });

    test('should validate name with proper trimming', () {
      // Nombre con espacios - debe limpiar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingName',
        '  Alberto  ',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('Alberto'));
    });

    test('should accept AUTO_GENERATE_STORY flag for meet story', () {
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingMeetStory',
        'AUTO_GENERATE_STORY',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('AUTO_GENERATE_STORY'));
    });

    test('should accept user provided meet story', () {
      final story =
          'Nos conocimos en una cafetería en Madrid, él se acercó y me ofreció un libro.';
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingMeetStory',
        story,
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals(story));
    });

    test('should accept ai name and trim', () {
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingAiName',
        'Yuna',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('Yuna'));
    });

    test('should accept ai country value', () {
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingAiCountry',
        'JP',
      );

      expect(result['isValid'], isTrue);
      expect(result['processedValue'], equals('JP'));
    });

    test('should reject empty or whitespace-only names', () {
      // Nombre vacío - debe fallar
      final result = ConversationalOnboardingService.validateAndSaveData(
        'askingName',
        '   ',
      );

      expect(result['isValid'], isFalse);
      expect(result['reason'], contains('Nombre'));
    });

    group('Date Format Validation', () {
      test('should accept DD/MM/YYYY format', () {
        final result = ConversationalOnboardingService.validateAndSaveData(
          'askingBirthdate',
          '25/12/1995',
        );

        expect(result['isValid'], isTrue);
      });

      test('should accept "nacido" or date keywords', () {
        final result = ConversationalOnboardingService.validateAndSaveData(
          'askingBirthdate',
          'Nací el 25 de diciembre de 1995',
        );

        expect(result['isValid'], isTrue);
      });

      test('should reject non-date text', () {
        final result = ConversationalOnboardingService.validateAndSaveData(
          'askingBirthdate',
          'No recuerdo exactamente',
        );

        expect(result['isValid'], isFalse);
      });
    });
  });
}
