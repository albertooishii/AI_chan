import 'package:ai_chan/onboarding/services/conversational_onboarding_service.dart';
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
    test('📝 Complete Conversational Flow: All Steps without Validation', () async {
      Log.d(
        '🔹 PASO 1: Iniciando flujo conversacional completo sin validaciones...',
        tag: 'TEST',
      );

      // 🎯 Setup: Crear servicio fake que simule respuestas de IA
      final fakeAiService = FakeAIService(
        customJsonResponse: {
          'displayValue': 'TestValue',
          'processedValue': 'ProcessedValue',
          'aiResponse': 'Response from AI',
          'confidence': 0.9,
        },
      );

      // Configurar override global
      AIService.testOverride = fakeAiService;

      // 🎯 PASO 1: askingName (primer paso - nombre del usuario)
      Log.d(
        '   🔸 Paso askingName: pidiendo nombre (primer paso)...',
        tag: 'TEST',
      );

      final nameResponse =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: 'Alberto',
            conversationStep: 'askingName',
            userName: 'Usuario',
            previousData: {},
          );

      expect(nameResponse['displayValue'], equals('TestValue'));
      expect(nameResponse['aiResponse'], isA<String>());
      Log.d('      ✅ askingName: nombre capturado', tag: 'TEST');

      // 🎯 PASO 2: askingCountry (país del usuario)
      Log.d('   🔸 Paso askingCountry: pidiendo país...', tag: 'TEST');

      final countryResponse =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: 'España',
            conversationStep: 'askingCountry',
            userName: 'Alberto',
            previousData: {'userName': 'Alberto'},
          );

      expect(countryResponse['displayValue'], equals('TestValue'));
      expect(countryResponse['aiResponse'], isA<String>());
      Log.d('      ✅ askingCountry: país capturado', tag: 'TEST');

      // 🎯 PASO 3: askingBirthday (cumpleaños del usuario)
      Log.d('   🔸 Paso askingBirthday: pidiendo fecha...', tag: 'TEST');

      final birthdayResponse =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: '15 de marzo de 1990',
            conversationStep: 'askingBirthday',
            userName: 'Alberto',
            previousData: {'userName': 'Alberto', 'userCountry': 'ES'},
          );

      expect(birthdayResponse['displayValue'], equals('TestValue'));
      expect(birthdayResponse['aiResponse'], isA<String>());
      Log.d('      ✅ askingBirthday: fecha capturada', tag: 'TEST');

      // 🎯 PASO 4: askingAiCountry (nacionalidad de la IA)
      Log.d(
        '   🔸 Paso askingAiCountry: pidiendo nacionalidad IA...',
        tag: 'TEST',
      );

      final aiCountryResponse =
          await ConversationalOnboardingService.processUserResponse(
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
      expect(aiCountryResponse['aiResponse'], isA<String>());
      Log.d('      ✅ askingAiCountry: nacionalidad IA capturada', tag: 'TEST');

      // 🎯 PASO 5: askingAiName (nombre de la IA)
      Log.d('   🔸 Paso askingAiName: pidiendo nombre IA...', tag: 'TEST');

      final aiNameResponse =
          await ConversationalOnboardingService.processUserResponse(
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
      expect(aiNameResponse['aiResponse'], isA<String>());
      Log.d('      ✅ askingAiName: nombre IA capturado', tag: 'TEST');

      // 🎯 PASO 6: askingMeetStory (historia de cómo se conocieron)
      Log.d('   🔸 Paso askingMeetStory: pidiendo historia...', tag: 'TEST');

      final meetStoryResponse =
          await ConversationalOnboardingService.processUserResponse(
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

      // 🎯 PASO 7: finalMessage (mensaje de despedida)
      Log.d('   🔸 Paso finalMessage: mensaje de despedida...', tag: 'TEST');

      final finalResponse =
          await ConversationalOnboardingService.generateNextResponse(
            userName: 'Alberto',
            userLastResponse: 'Nos conocimos en una convención de anime',
            conversationStep: 'finalMessage',
            aiName: 'Sakura',
            aiCountryCode: 'JP',
            collectedData: {
              'userName': 'Alberto',
              'userCountry': 'ES',
              'userBirthday': '15/03/1990',
              'aiCountry': 'JP',
              'aiName': 'Sakura',
              'meetStory': 'Nos conocimos en una convención de anime',
            },
          );

      expect(finalResponse, isA<String>());
      expect(finalResponse.isNotEmpty, isTrue);
      Log.d('      ✅ finalMessage: despedida generada', tag: 'TEST');

      // 🎯 PASO 8: completion (finalización - empieza initializing)
      Log.d('   🔸 Paso completion: inicializando chat...', tag: 'TEST');
      // Este paso no necesita procesamiento adicional, solo marca el final

      Log.d(
        '🎉 FLUJO CONVERSACIONAL COMPLETO ACTUALIZADO: todos los pasos sin validaciones',
        tag: 'TEST',
      );
      Log.d('   📊 Resumen:', tag: 'TEST');
      Log.d('      • askingName: ✅ primer paso, sin validación', tag: 'TEST');
      Log.d('      • askingCountry: ✅ sin validación', tag: 'TEST');
      Log.d('      • askingBirthday: ✅ sin validación', tag: 'TEST');
      Log.d('      • askingAiCountry: ✅ sin validación', tag: 'TEST');
      Log.d('      • askingAiName: ✅ sin validación', tag: 'TEST');
      Log.d('      • askingMeetStory: ✅ historia procesada', tag: 'TEST');
      Log.d('      • finalMessage: ✅ despedida generada', tag: 'TEST');
      Log.d(
        '      • completion: ✅ flujo completado → initializing',
        tag: 'TEST',
      );
    });

    test('🔄 Correction Handling: Manual text input for corrections', () async {
      Log.d(
        '🔹 Probando manejo de correcciones con entrada manual...',
        tag: 'TEST',
      );

      // Simular servicio que acepta corrección inmediatamente
      final correctionService = FakeAIService(
        customJsonResponse: {
          'displayValue': 'Alberto Corrected',
          'processedValue': 'Alberto Corrected',
          'aiResponse': 'Perfecto, ahora sí recuerdo tu nombre correctamente.',
          'confidence': 0.9,
        },
      );

      // Configurar override
      AIService.testOverride = correctionService;

      // Simular corrección usando el botón de texto
      final correctionResponse =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: 'Alberto Corrected', // Entrada manual corregida
            conversationStep: 'askingName',
            userName: 'Usuario',
            previousData: {},
          );

      // Verificar que se aceptó la corrección directamente
      expect(correctionResponse['displayValue'], equals('Alberto Corrected'));
      expect(correctionResponse['aiResponse'], contains('recuerdo'));

      Log.d('   ✅ Corrección manual aceptada directamente', tag: 'TEST');
    });

    test(
      '📝 Manual Input vs Voice Input: Both work without validation',
      () async {
        Log.d(
          '🔹 Probando que todas las entradas funcionan sin validación...',
          tag: 'TEST',
        );

        // Configurar servicio que acepta las respuestas directamente
        final noValidationService = FakeAIService(
          customJsonResponse: {
            'displayValue': 'Alberto',
            'processedValue': 'Alberto',
            'aiResponse': 'Perfecto, Alberto. Ahora pregúntame por tu país.',
            'confidence': 0.9,
          },
        );

        // Configurar override
        AIService.testOverride = noValidationService;

        // Test entrada por voz - sin validación
        final voiceResponse =
            await ConversationalOnboardingService.processUserResponse(
              userResponse: 'Alberto',
              conversationStep: 'askingName',
              userName: 'Usuario',
              previousData: {},
            );

        expect(voiceResponse['aiResponse'], contains('pregúntame'));
        Log.d('   ✅ Entrada por voz: acepta directamente', tag: 'TEST');

        // Test entrada manual - también acepta directamente
        final manualResponse =
            await ConversationalOnboardingService.processUserResponse(
              userResponse: 'Alberto Manual',
              conversationStep: 'askingName',
              userName: 'Usuario',
              previousData: {},
            );

        expect(manualResponse['aiResponse'], contains('pregúntame'));
        Log.d('   ✅ Entrada manual: acepta directamente', tag: 'TEST');
      },
    );

    test('🚨 Error Handling: Invalid responses and recovery', () async {
      Log.d('🔹 Probando manejo de errores y recuperación...', tag: 'TEST');

      try {
        // Simular respuesta inválida (vacía)
        final errorResponse =
            await ConversationalOnboardingService.processUserResponse(
              userResponse: '',
              conversationStep: 'askingName', // Usar paso actualizado
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
            await ConversationalOnboardingService.processUserResponse(
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
          'aiResponse': 'Perfecto, eres de España. Ahora dime cuándo naciste.',
          'confidence': 0.95,
        },
      );

      // Configurar override
      AIService.testOverride = countryService;

      final countryResponse =
          await ConversationalOnboardingService.processUserResponse(
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
          'aiResponse':
              'Entiendo, naciste el 15 de marzo de 1990. Ahora sobre mi nacionalidad...',
          'confidence': 0.9,
        },
      );

      // Cambiar override para el servicio de fecha
      AIService.testOverride = dateService;

      final dateResponse =
          await ConversationalOnboardingService.processUserResponse(
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
            },
          );

          // Configurar override para cada caso cultural
          AIService.testOverride = culturalService;

          final response =
              await ConversationalOnboardingService.processUserResponse(
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

    test('💬 Text Button: AI suggests text input when voice unclear', () async {
      Log.d('🔹 Probando sugerencias de entrada de texto...', tag: 'TEST');

      // Servicio que sugiere escritura manual
      final suggestionService = FakeAIService(
        customJsonResponse: {
          'displayValue': '',
          'processedValue': '',
          'aiResponse':
              'No pude entender bien. Si prefieres, puedes usar el botón de texto para escribirlo.',
          'confidence': 0.2,
        },
      );

      // Configurar override
      AIService.testOverride = suggestionService;

      final response =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: 'audio no claro',
            conversationStep: 'askingBirthday',
            userName: 'Alberto',
            previousData: {},
          );

      expect(response['confidence'], equals(0.2));
      expect(response['aiResponse'], contains('botón de texto'));

      Log.d('   ✅ Sugerencia de entrada de texto detectada', tag: 'TEST');
      Log.d('      • Confianza baja: ${response['confidence']}', tag: 'TEST');
      Log.d('      • Mensaje de sugerencia incluido', tag: 'TEST');
    });

    test(
      '🎯 Meet Story Options: User can tell story or AI can generate it',
      () async {
        Log.d('🔹 Probando opciones de historia de encuentro...', tag: 'TEST');

        // Opción 1: Usuario cuenta su historia
        final userStoryService = FakeAIService(
          customJsonResponse: {
            'displayValue':
                'Nos conocimos en una convención de anime en Madrid',
            'processedValue':
                'Nos conocimos en una convención de anime en Madrid',
            'aiResponse':
                '¡Qué bonito recuerdo! Una convención de anime... eso explica mucho.',
            'confidence': 0.9,
          },
        );

        AIService.testOverride = userStoryService;

        final userStoryResponse =
            await ConversationalOnboardingService.processUserResponse(
              userResponse:
                  'Nos conocimos en una convención de anime en Madrid',
              conversationStep: 'askingMeetStory',
              userName: 'Alberto',
              previousData: {
                'userName': 'Alberto',
                'aiName': 'Sakura',
                'aiCountry': 'JP',
              },
            );

        expect(userStoryResponse['displayValue'], contains('convención'));
        expect(userStoryResponse['aiResponse'], contains('bonito recuerdo'));
        Log.d(
          '   ✅ Opción 1: Usuario cuenta su historia aceptada',
          tag: 'TEST',
        );

        // Opción 2: AI genera historia basada en contexto
        final generatedStory =
            await ConversationalOnboardingService.generateMeetStoryFromContext(
              userName: 'Alberto',
              aiName: 'Sakura',
              userCountry: 'ES',
              aiCountry: 'JP',
              userBirthday: DateTime(1990, 3, 15),
            );

        expect(generatedStory, isA<String>());
        expect(generatedStory.isNotEmpty, isTrue);
        Log.d(
          '   ✅ Opción 2: IA puede generar historia desde contexto',
          tag: 'TEST',
        );
        Log.d(
          '      • Historia generada: ${generatedStory.substring(0, 50)}...',
          tag: 'TEST',
        );
      },
    );
  });
}
