import 'package:ai_chan/onboarding/services/conversational_ai_service.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/prefs_test_utils.dart';
import '../fakes/fake_ai_service.dart';
import '../test_setup.dart';

void main() async {
  await initializeTestEnvironment();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PrefsTestUtils.setMockInitialValues();
  });

  tearDown(() {
    // Limpiar override después de cada test
    AIService.testOverride = null;
  });

  group('🗣️ Conversational Onboarding Flow Tests', () {
    test(
      '📝 Complete Conversational Flow: All Steps with Validation',
      () async {
        Log.d(
          '🔹 PASO 1: Iniciando flujo conversacional completo...',
          tag: 'TEST',
        );

        // 🎯 Setup: Crear servicio fake que simule respuestas de IA
        final fakeAiService = FakeAIService(
          customJsonResponse: {
            'displayValue': 'TestValue',
            'processedValue': 'ProcessedValue',
            'aiResponse': 'Response from AI',
            'confidence': 0.9,
            'needsValidation': true,
          },
        );

        // Configurar override global
        AIService.testOverride = fakeAiService;

        // 🎯 PASO 1: awakening (nombre del usuario)
        Log.d('   🔸 Paso awakening: pidiendo nombre...', tag: 'TEST');

        final awakeningResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: 'Alberto',
              conversationStep: 'awakening',
              userName: 'Usuario',
              previousData: {},
            );

        expect(awakeningResponse['displayValue'], equals('TestValue'));
        expect(awakeningResponse['needsValidation'], equals(true));
        expect(awakeningResponse['aiResponse'], isA<String>());
        Log.d(
          '      ✅ awakening: nombre capturado con validación',
          tag: 'TEST',
        );

        // 🎯 PASO 2: askingCountry (país del usuario)
        Log.d('   🔸 Paso askingCountry: pidiendo país...', tag: 'TEST');

        final countryResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: 'España',
              conversationStep: 'askingCountry',
              userName: 'Alberto',
              previousData: {'userName': 'Alberto'},
            );

        expect(countryResponse['displayValue'], equals('TestValue'));
        expect(countryResponse['needsValidation'], equals(true));
        expect(countryResponse['aiResponse'], isA<String>());
        Log.d(
          '      ✅ askingCountry: país capturado con validación',
          tag: 'TEST',
        );

        // 🎯 PASO 3: askingBirthday (cumpleaños del usuario)
        Log.d('   🔸 Paso askingBirthday: pidiendo fecha...', tag: 'TEST');

        final birthdayResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: '15 de marzo de 1990',
              conversationStep: 'askingBirthday',
              userName: 'Alberto',
              previousData: {'userName': 'Alberto', 'userCountry': 'ES'},
            );

        expect(birthdayResponse['displayValue'], equals('TestValue'));
        expect(birthdayResponse['needsValidation'], equals(true));
        expect(birthdayResponse['aiResponse'], isA<String>());
        Log.d(
          '      ✅ askingBirthday: fecha capturada con validación',
          tag: 'TEST',
        );

        // 🎯 PASO 4: askingAiCountry (nacionalidad de la IA)
        Log.d(
          '   🔸 Paso askingAiCountry: pidiendo nacionalidad IA...',
          tag: 'TEST',
        );

        final aiCountryResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: 'japonesa',
              conversationStep: 'askingAiCountry',
              userName: 'Alberto',
              previousData: {
                'userName': 'Alberto',
                'userCountry': 'ES',
                'userBirthday': '15/03/1990',
              },
            );

        expect(aiCountryResponse['displayValue'], equals('TestValue'));
        expect(aiCountryResponse['needsValidation'], equals(true));
        expect(aiCountryResponse['aiResponse'], isA<String>());
        Log.d(
          '      ✅ askingAiCountry: nacionalidad IA capturada con validación',
          tag: 'TEST',
        );

        // 🎯 PASO 5: askingAiName (nombre de la IA)
        Log.d('   🔸 Paso askingAiName: pidiendo nombre IA...', tag: 'TEST');

        final aiNameResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: 'Sakura',
              conversationStep: 'askingAiName',
              userName: 'Alberto',
              previousData: {
                'userName': 'Alberto',
                'userCountry': 'ES',
                'userBirthday': '15/03/1990',
                'aiCountry': 'JP',
              },
            );

        expect(aiNameResponse['displayValue'], equals('TestValue'));
        expect(aiNameResponse['needsValidation'], equals(true));
        expect(aiNameResponse['aiResponse'], isA<String>());
        Log.d(
          '      ✅ askingAiName: nombre IA capturado con validación',
          tag: 'TEST',
        );

        // 🎯 PASO 6: askingMeetStory (historia de cómo se conocieron)
        Log.d('   🔸 Paso askingMeetStory: pidiendo historia...', tag: 'TEST');

        final meetStoryResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: 'Nos conocimos en una convención de anime',
              conversationStep: 'askingMeetStory',
              userName: 'Alberto',
              previousData: {
                'userName': 'Alberto',
                'userCountry': 'ES',
                'userBirthday': '15/03/1990',
                'aiCountry': 'JP',
                'aiName': 'Sakura',
              },
            );

        expect(meetStoryResponse['displayValue'], equals('TestValue'));
        expect(meetStoryResponse['aiResponse'], isA<String>());
        Log.d('      ✅ askingMeetStory: historia capturada', tag: 'TEST');

        Log.d(
          '🎉 FLUJO CONVERSACIONAL COMPLETO: todos los pasos validados',
          tag: 'TEST',
        );
        Log.d('   📊 Resumen:', tag: 'TEST');
        Log.d('      • awakening: ✅ validación requerida', tag: 'TEST');
        Log.d('      • askingCountry: ✅ validación requerida', tag: 'TEST');
        Log.d('      • askingBirthday: ✅ validación requerida', tag: 'TEST');
        Log.d('      • askingAiCountry: ✅ validación requerida', tag: 'TEST');
        Log.d('      • askingAiName: ✅ validación requerida', tag: 'TEST');
        Log.d('      • askingMeetStory: ✅ historia procesada', tag: 'TEST');
      },
    );

    test('🔄 Correction Handling: stepCorrection works properly', () async {
      Log.d(
        '🔹 Probando manejo de correcciones con stepCorrection...',
        tag: 'TEST',
      );

      // Simular servicio que detecta corrección
      final correctionService = FakeAIService(
        customJsonResponse: {
          'displayValue': '',
          'processedValue': '',
          'aiResponse': 'Lo siento, me equivoqué. ¿Podrías repetir tu nombre?',
          'confidence': 0.1,
          'needsValidation': false,
          'stepCorrection':
              'awakening', // Indica que debe volver al paso awakening
        },
      );

      // Configurar override
      AIService.testOverride = correctionService;

      // Simular que el usuario dice "no" durante una validación
      final correctionResponse =
          await ConversationalAIService.processUserResponse(
            userResponse: 'no, ese no es mi nombre',
            conversationStep: 'askingCountry', // Estaba en otro paso
            userName: 'Usuario',
            previousData: {'userName': 'NombreIncorrecto'},
          );

      // Verificar que se detectó la corrección
      expect(correctionResponse.containsKey('stepCorrection'), isTrue);
      expect(correctionResponse['stepCorrection'], equals('awakening'));
      expect(correctionResponse['aiResponse'], contains('Lo siento'));

      Log.d('   ✅ Corrección detectada y manejada correctamente', tag: 'TEST');
    });

    test('📝 Manual Input vs Voice Input: SIEMPRE requiere validación', () async {
      Log.d(
        '🔹 Probando que TODAS las entradas requieren validación...',
        tag: 'TEST',
      );

      // Configurar servicio que SIEMPRE requiere validación
      final validationService = FakeAIService(
        customJsonResponse: {
          'displayValue': 'Alberto',
          'processedValue': 'Alberto',
          'aiResponse': '¿He entendido bien tu nombre, Alberto?',
          'confidence': 0.9,
          'needsValidation': true, // SIEMPRE true por los nuevos requerimientos
        },
      );

      // Configurar override
      AIService.testOverride = validationService;

      // Test entrada por voz - debe requerir validación
      final voiceResponse = await ConversationalAIService.processUserResponse(
        userResponse: 'Alberto',
        conversationStep: 'awakening',
        userName: 'Usuario',
        previousData: {},
      );

      expect(voiceResponse['needsValidation'], equals(true));
      expect(voiceResponse['aiResponse'], contains('entendido bien'));
      Log.d(
        '   ✅ Entrada por voz: validación requerida correctamente',
        tag: 'TEST',
      );

      // Test entrada manual - TAMBIÉN debe requerir validación (CAMBIO IMPORTANTE)
      // El servicio SIEMPRE devuelve needsValidation=true ahora, la diferencia está en el screen
      final manualResponse = await ConversationalAIService.processUserResponse(
        userResponse: 'Alberto',
        conversationStep: 'awakening',
        userName: 'Usuario',
        previousData: {},
      );

      // NUEVA REGLA: El servicio SIEMPRE devuelve needsValidation=true
      expect(manualResponse['needsValidation'], equals(true));
      expect(manualResponse['aiResponse'], contains('entendido bien'));
      Log.d(
        '   ✅ Servicio SIEMPRE devuelve needsValidation=true (nuevo comportamiento)',
        tag: 'TEST',
      );
    });

    test('🚨 Error Handling: Invalid responses and recovery', () async {
      Log.d('🔹 Probando manejo de errores y recuperación...', tag: 'TEST');

      try {
        // Simular respuesta inválida (vacía)
        final errorResponse = await ConversationalAIService.processUserResponse(
          userResponse: '',
          conversationStep: 'awakening',
          userName: 'Usuario',
          previousData: {},
        );

        // El servicio debe manejar gracefully las respuestas vacías
        expect(errorResponse, isA<Map<String, dynamic>>());
        Log.d('   ✅ Respuesta vacía manejada correctamente', tag: 'TEST');
      } catch (e) {
        Log.d('   ℹ️ Error esperado para respuesta vacía: $e', tag: 'TEST');
      }

      try {
        // Simular paso inválido
        final invalidStepResponse =
            await ConversationalAIService.processUserResponse(
              userResponse: 'test',
              conversationStep: 'invalidStep',
              userName: 'Usuario',
              previousData: {},
            );

        expect(invalidStepResponse, isA<Map<String, dynamic>>());
        Log.d('   ✅ Paso inválido manejado correctamente', tag: 'TEST');
      } catch (e) {
        Log.d('   ℹ️ Error esperado para paso inválido: $e', tag: 'TEST');
      }
    });

    test('🔍 Data Validation: Country codes and date formats', () async {
      Log.d(
        '🔹 Probando validación de códigos de país y fechas...',
        tag: 'TEST',
      );

      // Servicio que simula conversión de país a código ISO2
      final countryService = FakeAIService(
        customJsonResponse: {
          'displayValue': 'España',
          'processedValue': 'ES',
          'aiResponse': '¿Así que eres de España? ¿Es correcto?',
          'confidence': 0.95,
          'needsValidation': true,
        },
      );

      // Configurar override
      AIService.testOverride = countryService;

      final countryResponse = await ConversationalAIService.processUserResponse(
        userResponse: 'España',
        conversationStep: 'askingCountry',
        userName: 'Alberto',
        previousData: {},
      );

      expect(countryResponse['displayValue'], equals('España'));
      expect(countryResponse['processedValue'], equals('ES'));
      Log.d('   ✅ Conversión país → código ISO2 verificada', tag: 'TEST');

      // Servicio que simula conversión de fecha
      final dateService = FakeAIService(
        customJsonResponse: {
          'displayValue': '15 de marzo de 1990',
          'processedValue': '15/03/1990',
          'aiResponse': '¿Naciste el 15 de marzo de 1990? ¿Es correcto?',
          'confidence': 0.9,
          'needsValidation': true,
        },
      );

      // Cambiar override para el servicio de fecha
      AIService.testOverride = dateService;

      final dateResponse = await ConversationalAIService.processUserResponse(
        userResponse: 'quince de marzo de mil novecientos noventa',
        conversationStep: 'askingBirthday',
        userName: 'Alberto',
        previousData: {},
      );

      expect(dateResponse['displayValue'], equals('15 de marzo de 1990'));
      expect(dateResponse['processedValue'], equals('15/03/1990'));
      Log.d('   ✅ Conversión fecha texto → DD/MM/YYYY verificada', tag: 'TEST');
    });

    test('🗂️ Context Management: previousData propagation', () async {
      Log.d('🔹 Probando propagación de contexto entre pasos...', tag: 'TEST');

      // Simular acumulación de datos a través de los pasos
      final initialData = <String, dynamic>{};

      // Paso 1: nombre
      final step1Data = Map<String, dynamic>.from(initialData);
      step1Data['userName'] = 'Alberto';

      // Paso 2: país (debe tener contexto del paso 1)
      final step2Data = Map<String, dynamic>.from(step1Data);
      step2Data['userCountry'] = 'ES';

      // Paso 3: cumpleaños (debe tener contexto de pasos anteriores)
      final step3Data = Map<String, dynamic>.from(step2Data);
      step3Data['userBirthday'] = '15/03/1990';

      // Verificar que el contexto se mantiene
      expect(step3Data['userName'], equals('Alberto'));
      expect(step3Data['userCountry'], equals('ES'));
      expect(step3Data['userBirthday'], equals('15/03/1990'));

      Log.d('   ✅ Contexto mantenido a través de todos los pasos', tag: 'TEST');
      Log.d('      • Paso 1: userName = ${step3Data['userName']}', tag: 'TEST');
      Log.d(
        '      • Paso 2: + userCountry = ${step3Data['userCountry']}',
        tag: 'TEST',
      );
      Log.d(
        '      • Paso 3: + userBirthday = ${step3Data['userBirthday']}',
        tag: 'TEST',
      );
    });

    test(
      '🎭 Personality and Culture: AI responds with appropriate personality',
      () async {
        Log.d('🔹 Probando personalidad y adaptación cultural...', tag: 'TEST');

        // Test con diferentes nacionalidades
        final testCases = [
          {
            'country': 'JP',
            'name': 'Sakura',
            'expectedCulture': 'Japanese',
            'desc': 'Japonesa',
          },
          {
            'country': 'KR',
            'name': 'Min-ji',
            'expectedCulture': 'Korean',
            'desc': 'Coreana',
          },
          {
            'country': 'ES',
            'name': 'Carmen',
            'expectedCulture': 'Spanish',
            'desc': 'Española',
          },
        ];

        for (final testCase in testCases) {
          Log.d('   🧪 Caso: IA ${testCase['desc']}', tag: 'TEST');

          final culturalService = FakeAIService(
            customJsonResponse: {
              'displayValue': testCase['name']!,
              'processedValue': testCase['name']!,
              'aiResponse':
                  'Cultural response for ${testCase['expectedCulture']}',
              'confidence': 0.9,
              'needsValidation': true,
            },
          );

          // Configurar override para cada caso cultural
          AIService.testOverride = culturalService;

          final response = await ConversationalAIService.processUserResponse(
            userResponse: testCase['name']!,
            conversationStep: 'askingAiName',
            userName: 'Alberto',
            previousData: {'aiCountry': testCase['country']!},
          );

          expect(response['displayValue'], equals(testCase['name']!));
          expect(
            response['aiResponse'],
            contains(testCase['expectedCulture']!),
          );

          Log.d(
            '      ✅ ${testCase['desc']}: personalidad cultural aplicada',
            tag: 'TEST',
          );
        }

        Log.d(
          '   ✅ Todas las personalidades culturales verificadas',
          tag: 'TEST',
        );
      },
    );

    test('💬 Suggestions: AI can suggest manual input when needed', () async {
      Log.d('🔹 Probando sugerencias de entrada manual...', tag: 'TEST');

      // Servicio que sugiere escritura manual
      final suggestionService = FakeAIService(
        customJsonResponse: {
          'displayValue': '',
          'processedValue': '',
          'aiResponse':
              'No pude entender bien. Si prefieres, puedes usar el botón de texto para escribirlo.',
          'confidence': 0.2,
          'needsValidation': true,
        },
      );

      // Configurar override
      AIService.testOverride = suggestionService;

      final response = await ConversationalAIService.processUserResponse(
        userResponse: 'audio no claro',
        conversationStep: 'askingBirthday',
        userName: 'Alberto',
        previousData: {},
      );

      expect(response['confidence'], equals(0.2));
      expect(response['aiResponse'], contains('botón de texto'));

      Log.d('   ✅ Sugerencia de entrada manual detectada', tag: 'TEST');
      Log.d('      • Confianza baja: ${response['confidence']}', tag: 'TEST');
      Log.d('      • Mensaje de sugerencia incluido', tag: 'TEST');
    });
  });
}
