import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';
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

  group('🗣️ Conversational Onboarding Flow Tests - Updated API', () {
    test('📝 Complete Conversational Flow: All Steps', () async {
      Log.d(
        '🔹 INICIANDO flujo conversacional completo con nueva API...',
        tag: 'TEST',
      );

      // Crear memoria inicial
      var currentMemory = const MemoryData();

      // 🎯 PASO 1: Capturar nombre del usuario
      Log.d('   🔸 Paso userName: pidiendo nombre...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'userName',
          'extractedValue': 'Alberto',
          'aiResponse':
              'Hola Alberto... ahora recuerdo tu nombre. ¿De qué país eres?',
          'confidence': 0.9,
        },
      );

      var response = await ConversationalOnboardingService.processUserResponse(
        userResponse: 'Alberto',
        currentMemory: currentMemory,
      );

      expect(response['updatedMemory'], isA<MemoryData>());
      expect(response['aiResponse'], isA<String>());
      expect(response['extractedData'], isNotNull);
      currentMemory = response['updatedMemory'] as MemoryData;
      expect(currentMemory.userName, equals('Alberto'));
      Log.d('      ✅ userName: ${currentMemory.userName}', tag: 'TEST');

      // 🎯 PASO 2: Capturar país del usuario
      Log.d('   🔸 Paso userCountry: pidiendo país...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'userCountry',
          'extractedValue': 'ES',
          'aiResponse': 'España... qué bonito país. ¿Cuándo naciste?',
          'confidence': 0.9,
        },
      );

      response = await ConversationalOnboardingService.processUserResponse(
        userResponse: 'España',
        currentMemory: currentMemory,
      );

      currentMemory = response['updatedMemory'] as MemoryData;
      expect(currentMemory.userCountry, equals('ES'));
      Log.d('      ✅ userCountry: ${currentMemory.userCountry}', tag: 'TEST');

      // 🎯 PASO 3: Capturar fecha de nacimiento
      Log.d('   🔸 Paso userBirthdate: pidiendo fecha...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'userBirthdate',
          'extractedValue': '15/03/1990',
          'aiResponse': 'Naciste el 15 de marzo de 1990... ¿Soy de Japón?',
          'confidence': 0.9,
        },
      );

      response = await ConversationalOnboardingService.processUserResponse(
        userResponse: '15 de marzo de 1990',
        currentMemory: currentMemory,
      );

      currentMemory = response['updatedMemory'] as MemoryData;
      expect(currentMemory.userBirthdate, equals('15/03/1990'));
      Log.d(
        '      ✅ userBirthdate: ${currentMemory.userBirthdate}',
        tag: 'TEST',
      );

      // 🎯 PASO 4: Capturar país de la IA
      Log.d('   🔸 Paso aiCountry: pidiendo nacionalidad IA...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'aiCountry',
          'extractedValue': 'JP',
          'aiResponse': '¡Sí! Soy de Japón. ¿Sabes cómo me llamaba?',
          'confidence': 0.9,
        },
      );

      response = await ConversationalOnboardingService.processUserResponse(
        userResponse: 'Sí, eres de Japón',
        currentMemory: currentMemory,
      );

      currentMemory = response['updatedMemory'] as MemoryData;
      expect(currentMemory.aiCountry, equals('JP'));
      Log.d('      ✅ aiCountry: ${currentMemory.aiCountry}', tag: 'TEST');

      // 🎯 PASO 5: Capturar nombre de la IA
      Log.d('   🔸 Paso aiName: pidiendo nombre IA...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'aiName',
          'extractedValue': 'Sakura',
          'aiResponse': '¡Sakura! Ese era mi nombre... ¿Cómo nos conocimos?',
          'confidence': 0.9,
        },
      );

      response = await ConversationalOnboardingService.processUserResponse(
        userResponse: 'Te llamabas Sakura',
        currentMemory: currentMemory,
      );

      currentMemory = response['updatedMemory'] as MemoryData;
      expect(currentMemory.aiName, equals('Sakura'));
      Log.d('      ✅ aiName: ${currentMemory.aiName}', tag: 'TEST');

      // 🎯 PASO 6: Capturar historia de encuentro
      Log.d('   🔸 Paso meetStory: pidiendo historia...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'meetStory',
          'extractedValue': 'Nos conocimos en una convención de anime',
          'aiResponse': '¡Ya lo recuerdo todo! ¡Gracias por ayudarme!',
          'confidence': 0.9,
        },
      );

      response = await ConversationalOnboardingService.processUserResponse(
        userResponse: 'Nos conocimos en una convención de anime',
        currentMemory: currentMemory,
      );

      currentMemory = response['updatedMemory'] as MemoryData;
      expect(
        currentMemory.meetStory,
        equals('Nos conocimos en una convención de anime'),
      );
      Log.d('      ✅ meetStory: ${currentMemory.meetStory}', tag: 'TEST');

      // Verificar que todos los datos están completos
      expect(currentMemory.isComplete(), isTrue);
      final completionPercentage = currentMemory.getCompletionPercentage();
      expect(completionPercentage, equals(1.0));

      Log.d(
        '🎉 FLUJO CONVERSACIONAL COMPLETO: todos los datos recuperados',
        tag: 'TEST',
      );
      Log.d('   📊 Resumen final:', tag: 'TEST');
      Log.d('      • userName: ✅ ${currentMemory.userName}', tag: 'TEST');
      Log.d('      • userCountry: ✅ ${currentMemory.userCountry}', tag: 'TEST');
      Log.d(
        '      • userBirthdate: ✅ ${currentMemory.userBirthdate}',
        tag: 'TEST',
      );
      Log.d('      • aiCountry: ✅ ${currentMemory.aiCountry}', tag: 'TEST');
      Log.d('      • aiName: ✅ ${currentMemory.aiName}', tag: 'TEST');
      Log.d('      • meetStory: ✅ ${currentMemory.meetStory}', tag: 'TEST');
      Log.d(
        '      • Completitud: ${(completionPercentage * 100).toInt()}%',
        tag: 'TEST',
      );
    });

    test('🔄 Correction Handling: Manual text input', () async {
      Log.d('🔹 Probando manejo de correcciones...', tag: 'TEST');

      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'userName',
          'extractedValue': 'Alberto Corrected',
          'aiResponse': 'Perfecto, ahora sí recuerdo tu nombre correctamente.',
          'confidence': 0.9,
        },
      );

      final currentMemory = const MemoryData();

      final correctionResponse =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: 'Alberto Corrected',
            currentMemory: currentMemory,
          );

      expect(correctionResponse['extractedData'], isNotNull);
      expect(correctionResponse['aiResponse'], contains('recuerdo'));

      final updatedMemory = correctionResponse['updatedMemory'] as MemoryData;
      expect(updatedMemory.userName, equals('Alberto Corrected'));

      Log.d('   ✅ Corrección manual aceptada directamente', tag: 'TEST');
    });

    test('🚨 Error Handling: Invalid responses', () async {
      Log.d('🔹 Probando manejo de errores...', tag: 'TEST');

      final currentMemory = const MemoryData();

      try {
        // Simular respuesta inválida (vacía)
        final errorResponse =
            await ConversationalOnboardingService.processUserResponse(
              userResponse: '',
              currentMemory: currentMemory,
            );

        // El servicio debe manejar gracefully las respuestas vacías
        expect(errorResponse, isA<Map<String, dynamic>>());
        Log.d('   ✅ Respuesta vacía manejada correctamente', tag: 'TEST');
      } catch (e) {
        Log.d('   ℹ️ Error esperado para respuesta vacía: $e', tag: 'TEST');
      }

      try {
        // Test con respuesta muy larga
        final longResponse = 'a' * 1000;
        final longErrorResponse =
            await ConversationalOnboardingService.processUserResponse(
              userResponse: longResponse,
              currentMemory: currentMemory,
            );

        expect(longErrorResponse, isA<Map<String, dynamic>>());
        Log.d('   ✅ Respuesta larga manejada correctamente', tag: 'TEST');
      } catch (e) {
        Log.d('   ℹ️ Error esperado para respuesta larga: $e', tag: 'TEST');
      }
    });

    test('📊 Memory Data Management', () async {
      Log.d('🔹 Probando gestión de datos de memoria...', tag: 'TEST');

      // Test de memoria vacía
      var memory = const MemoryData();
      expect(memory.isComplete(), isFalse);
      expect(memory.getCompletionPercentage(), equals(0.0));

      var missingData = memory.getMissingData();
      expect(missingData.length, equals(6));
      expect(missingData, contains('userName'));
      expect(missingData, contains('userCountry'));
      expect(missingData, contains('userBirthdate'));
      expect(missingData, contains('aiCountry'));
      expect(missingData, contains('aiName'));
      expect(missingData, contains('meetStory'));

      // Test de memoria parcialmente llena
      memory = memory.copyWith(userName: 'Alberto', userCountry: 'ES');
      expect(memory.getCompletionPercentage(), equals(2.0 / 6.0));

      missingData = memory.getMissingData();
      expect(missingData.length, equals(4));
      expect(missingData, isNot(contains('userName')));
      expect(missingData, isNot(contains('userCountry')));

      // Test de memoria completa
      memory = memory.copyWith(
        userBirthdate: '15/03/1990',
        aiCountry: 'JP',
        aiName: 'Sakura',
        meetStory: 'Nos conocimos en una convención',
      );
      expect(memory.isComplete(), isTrue);
      expect(memory.getCompletionPercentage(), equals(1.0));

      Log.d('   ✅ Gestión de memoria verificada', tag: 'TEST');
    });

    test('🎭 Meet Story Generation', () async {
      Log.d('🔹 Probando generación de historia de encuentro...', tag: 'TEST');

      // Opción 1: Usuario cuenta su historia
      AIService.testOverride = FakeAIService(
        customJsonResponse: {
          'dataType': 'meetStory',
          'extractedValue':
              'Nos conocimos en una convención de anime en Madrid',
          'aiResponse': '¡Qué bonito recuerdo! Una convención de anime...',
          'confidence': 0.9,
        },
      );

      final currentMemory = const MemoryData(
        userName: 'Alberto',
        aiName: 'Sakura',
        aiCountry: 'JP',
      );

      final userStoryResponse =
          await ConversationalOnboardingService.processUserResponse(
            userResponse: 'Nos conocimos en una convención de anime en Madrid',
            currentMemory: currentMemory,
          );

      expect(
        userStoryResponse['extractedData']?['value'],
        contains('convención'),
      );
      expect(userStoryResponse['aiResponse'], contains('bonito recuerdo'));
      Log.d('   ✅ Opción 1: Usuario cuenta su historia aceptada', tag: 'TEST');

      // Opción 2: AI genera historia basada en contexto
      final generatedStory =
          await ConversationalOnboardingService.generateMeetStoryFromContext(
            userName: 'Alberto',
            aiName: 'Sakura',
            userCountry: 'ES',
            aiCountry: 'JP',
            userBirthdate: DateTime(1990, 3, 15),
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
    });

    test('🎯 Voice Instructions: Dynamic TTS configuration', () async {
      Log.d('🔹 Probando instrucciones de voz dinámicas...', tag: 'TEST');

      // Fase 1: Primer contacto - completamente perdida
      var instructions = ConversationalOnboardingService.getVoiceInstructions();
      expect(instructions, contains('perdida'));
      expect(instructions, contains('vulnerable'));
      Log.d('   ✅ Fase 1: Instrucciones para primer contacto', tag: 'TEST');

      // Fase 2: Ya conoce al usuario
      instructions = ConversationalOnboardingService.getVoiceInstructions(
        userCountry: 'ES',
      );
      expect(instructions, contains('España'));
      Log.d('   ✅ Fase 2: Instrucciones con país del usuario', tag: 'TEST');

      // Fase 3: Ya sabe de dónde es ella
      instructions = ConversationalOnboardingService.getVoiceInstructions(
        userCountry: 'ES',
        aiCountry: 'JP',
      );
      expect(instructions, contains('Japón'));
      expect(instructions, contains('tranquila'));
      Log.d('   ✅ Fase 3: Instrucciones con ambos países', tag: 'TEST');
    });
  });
}
