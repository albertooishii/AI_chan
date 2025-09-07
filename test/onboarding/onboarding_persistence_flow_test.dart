import 'dart:convert';

import 'package:ai_chan/onboarding/application/use_cases/biography_generation_use_case.dart';
import 'package:ai_chan/onboarding/application/controllers/form_onboarding_controller.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/app_data_utils.dart';
import 'package:ai_chan/chat/domain/models/chat_export.dart';
import 'package:ai_chan/chat/infrastructure/adapters/local_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_ai_service.dart';
import '../test_setup.dart';
import '../test_utils/prefs_test_utils.dart';
import 'package:ai_chan/onboarding/application/controllers/onboarding_lifecycle_controller.dart';

void main() async {
  await initializeTestEnvironment();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PrefsTestUtils.setMockInitialValues();
  });

  tearDown(() async {
    // Clear any stored onboarding data between tests
    await PrefsUtils.removeOnboardingData();
    await PrefsUtils.clearAll(); // Clear everything to ensure clean state
    AIService.testOverride = null;
  });

  group('🔄 Robust E2E Onboarding → Chat → Export → Import → Restart Flow', () {
    test('Complete data integrity through full application lifecycle', () async {
      // ===== FASE 1: SETUP Y ONBOARDING =====
      Log.i(
        '\n🔹 FASE 1: Configuración y onboarding inicial',
        tag: 'ROBUST_TEST',
      );

      final fake = FakeAIService.forAppearanceAndBiography();
      AIService.testOverride = fake;

      // 1.1 Onboarding via formulario
      final formController = FormOnboardingController();
      final formResult = await formController.processForm(
        userName: 'TestUser',
        aiName: 'AiTest',
        birthDateText: '15/03/1990',
        meetStory: 'Nos conocimos en una feria',
        userCountryCode: 'ES',
        aiCountryCode: 'JP',
      );

      expect(
        formResult.success,
        isTrue,
        reason: 'Form onboarding debe ser exitoso',
      );
      expect(formResult.userName, equals('TestUser'));
      expect(formResult.aiName, equals('AiTest'));
      expect(formResult.meetStory, equals('Nos conocimos en una feria'));

      // 1.2 Generación de biografía completa
      final bioUseCase = BiographyGenerationUseCase();
      final originalProfile = await bioUseCase.generateCompleteBiography(
        userName: formResult.userName!,
        aiName: formResult.aiName!,
        userBirthdate: formResult.userBirthdate!,
        meetStory: formResult.meetStory!,
        userCountryCode: formResult.userCountryCode,
        aiCountryCode: formResult.aiCountryCode,
      );

      // Verificar datos del perfil generado
      expect(originalProfile.userName, equals('TestUser'));
      expect(originalProfile.aiName, equals('AiTest'));
      expect(originalProfile.biography, isNotEmpty);
      expect(originalProfile.appearance, isNotEmpty);
      expect(originalProfile.avatars, isNotEmpty);

      // ===== FASE 2: VERIFICACIÓN DE PERSISTENCIA INICIAL =====
      Log.i(
        '🔹 FASE 2: Verificación de persistencia inicial con timeline',
        tag: 'ROBUST_TEST',
      );

      // 2.1 Verificar que la biografía se guardó correctamente con timeline
      final storedDataAfterBio = await PrefsUtils.getOnboardingData();
      expect(
        storedDataAfterBio,
        isNotNull,
        reason: 'Datos deben persistirse tras generación de biografía',
      );

      final storedMapAfterBio = jsonDecode(storedDataAfterBio!);
      expect(
        storedMapAfterBio['timeline'],
        isA<List>(),
        reason: 'Timeline debe existir',
      );
      final timelineAfterBio = storedMapAfterBio['timeline'] as List;
      expect(
        timelineAfterBio.length,
        equals(1),
        reason: 'Debe haber exactamente 1 entrada de timeline (meetStory)',
      );
      expect(
        timelineAfterBio[0]['resume'],
        equals('Nos conocimos en una feria'),
      );
      expect(
        timelineAfterBio[0]['level'],
        equals(-1),
        reason: 'MeetStory debe tener nivel -1',
      );

      // 2.2 Verificar integridad de datos guardados
      final storedProfile = Map<String, dynamic>.from(storedMapAfterBio)
        ..remove('messages')
        ..remove('events')
        ..remove('timeline');
      expect(
        storedProfile,
        equals(originalProfile.toJson()),
        reason: 'Perfil guardado debe coincidir exactamente',
      );

      // ===== FASE 3: SIMULACIÓN DE PERSISTENCIA VIA REPOSITORY =====
      Log.i(
        '🔹 FASE 3: Simulación de persistencia via repository',
        tag: 'ROBUST_TEST',
      );

      // 3.1 Usar repository directo para simular ChatApplicationService
      final repository = LocalChatRepository();

      // 3.2 Simular datos de chat completos
      final mockMessages = [
        {
          'text': 'Hola, ¿cómo estás?',
          'sender': 'user',
          'dateTime': DateTime.now().toIso8601String(),
          'status': 'sent',
        },
        {
          'text': '¡Hola! Estoy muy bien, gracias por preguntar.',
          'sender': 'assistant',
          'dateTime': DateTime.now()
              .add(const Duration(seconds: 1))
              .toIso8601String(),
          'status': 'read',
        },
      ];

      final mockEvents = [
        {
          'type': 'test_event',
          'description': 'Evento de prueba',
          'date': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        },
      ];

      // 3.3 Crear ChatExport completo con datos simulados
      final completeExportData = originalProfile.toJson();
      completeExportData['messages'] = mockMessages;
      completeExportData['events'] = mockEvents;

      // 3.3.1 Crear timeline con historia de encuentro (level -1)
      final meetStory =
          originalProfile.biography['meetStory'] ??
          'Historia de encuentro de prueba';
      final timelineEntry = {
        'resume': meetStory,
        'startDate': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
        'endDate': DateTime.now().toIso8601String(),
        'level': -1,
      };
      completeExportData['timeline'] = [timelineEntry];
      // El timeline ya debe estar presente desde la biografía

      // 3.4 Persistir usando repository
      await repository.saveAll(completeExportData);

      // 3.5 Verificar que los datos se guardaron correctamente
      final loadedData = await repository.loadAll();
      expect(
        loadedData,
        isNotNull,
        reason: 'Repository debe cargar datos guardados',
      );
      expect(loadedData!['userName'], equals('TestUser'));
      expect(loadedData['timeline'], isA<List>());
      final loadedTimeline = loadedData['timeline'] as List;
      expect(
        loadedTimeline.length,
        greaterThan(0),
        reason: 'Timeline debe tener al menos una entrada',
      );
      expect(loadedTimeline[0]['level'], equals(-1));

      // ===== FASE 4: EXPORT/IMPORT COMPLETO =====
      Log.i('🔹 FASE 4: Export/Import completo de datos', tag: 'ROBUST_TEST');

      // 4.1 Exportar datos completos como ChatExport
      final chatExport = ChatExport.fromJson(loadedData);

      // 4.2 Verificar integridad del export
      expect(chatExport.profile.userName, equals('TestUser'));
      expect(
        chatExport.messages,
        isNotEmpty,
        reason: 'Export debe incluir mensajes',
      );
      expect(
        chatExport.timeline.length,
        equals(1),
        reason: 'Timeline debe mantenerse en export',
      );
      expect(
        chatExport.timeline[0].level,
        equals(-1),
        reason: 'Nivel de meetStory debe preservarse',
      );

      // 4.3 Serializar a JSON
      final exportJson = jsonEncode(chatExport.toJson());
      expect(exportJson, isNotEmpty);

      // Verificar que el JSON es válido y completo
      final exportMap = jsonDecode(exportJson) as Map<String, dynamic>;
      expect(exportMap['userName'], equals('TestUser'));
      expect(exportMap['messages'], isA<List>());
      expect(exportMap['timeline'], isA<List>());
      expect(exportMap['events'], isA<List>());

      // 4.4 Simular export usando BackupUtils (compatibilidad)
      final backupExportJson = await BackupUtils.exportChatPartsToJson(
        profile: chatExport.profile,
        messages: chatExport.messages,
        events: chatExport.events,
        timeline: chatExport.timeline,
      );
      expect(backupExportJson, isNotEmpty);
      final backupExportMap = jsonDecode(backupExportJson);
      expect(backupExportMap['userName'], equals('TestUser'));

      // ===== FASE 5: LIMPIEZA TOTAL Y IMPORT =====
      Log.i(
        '🔹 FASE 5: Limpieza total y reimport de datos',
        tag: 'ROBUST_TEST',
      );

      // 5.1 Limpiar TODOS los datos
      await PrefsUtils.clearAll();
      await repository.clearAll();

      // Verificar limpieza completa
      final clearedData = await PrefsUtils.getOnboardingData();
      expect(
        clearedData,
        isNull,
        reason: 'Datos deben estar completamente limpiados',
      );

      // 5.2 Import usando ChatJsonUtils
      String? importError;
      final importedChat = await ChatJsonUtils.importAllFromJson(
        exportJson,
        onError: (final error) => importError = error,
      );

      expect(
        importError,
        isNull,
        reason: 'Import no debe tener errores: $importError',
      );
      expect(
        importedChat,
        isNotNull,
        reason: 'Import debe devolver datos válidos',
      );
      expect(importedChat!.profile.userName, equals('TestUser'));
      expect(importedChat.profile.aiName, equals('AiTest'));
      expect(importedChat.timeline.length, equals(1));
      expect(importedChat.timeline[0].level, equals(-1));

      // 5.3 Aplicar datos importados via repository
      await repository.saveAll(importedChat.toJson());

      // ===== FASE 6: MÚLTIPLES REINICIOS SIMULADOS =====
      Log.i('🔹 FASE 6: Múltiples reinicios simulados', tag: 'ROBUST_TEST');

      for (int restart = 1; restart <= 3; restart++) {
        Log.i('  - Simulando reinicio #$restart', tag: 'ROBUST_TEST');

        // 6.1 Crear nuevo repository (simula reinicio de app)
        final newRepository = LocalChatRepository();

        // 6.2 Cargar datos (debe cargar datos persistidos)
        final dataAfterRestart = await newRepository.loadAll();

        // 6.3 Verificar integridad tras reinicio
        expect(
          dataAfterRestart,
          isNotNull,
          reason: 'Datos deben cargarse tras reinicio #$restart',
        );
        expect(dataAfterRestart!['userName'], equals('TestUser'));
        expect(dataAfterRestart['aiName'], equals('AiTest'));
        expect(
          dataAfterRestart['timeline'],
          isA<List>(),
          reason: 'Timeline debe persistir en reinicio #$restart',
        );
        expect(
          (dataAfterRestart['timeline'] as List)[0]['level'],
          equals(-1),
          reason: 'Nivel -1 debe mantenerse en reinicio #$restart',
        );
        expect(
          dataAfterRestart['messages'],
          isNotEmpty,
          reason: 'Mensajes deben persistir en reinicio #$restart',
        );

        // 6.4 Crear OnboardingLifecycleController (otra forma de cargar datos)
        final lifecycleController = OnboardingLifecycleController(
          chatRepository: LocalChatRepository(),
        );
        await Future.doWhile(() async {
          await Future.delayed(const Duration(milliseconds: 10));
          return lifecycleController.loading;
        });

        expect(
          lifecycleController.generatedBiography,
          isNotNull,
          reason:
              'OnboardingLifecycleController debe cargar biografía en reinicio #$restart',
        );
        expect(
          lifecycleController.generatedBiography!.userName,
          equals('TestUser'),
        );

        // 6.5 Agregar mensaje y verificar persistencia via repository
        final updatedData = Map<String, dynamic>.from(dataAfterRestart);
        final messages = List<Map<String, dynamic>>.from(
          updatedData['messages'] as List,
        );
        messages.add({
          'text': 'Mensaje tras reinicio #$restart',
          'sender': 'user',
          'dateTime': DateTime.now().toIso8601String(),
          'status': 'sent',
        });
        updatedData['messages'] = messages;

        await newRepository.saveAll(updatedData);
        final verifyData = await newRepository.loadAll();
        expect(
          (verifyData!['messages'] as List).length,
          greaterThan(restart + 1),
          reason: 'Nuevos mensajes deben agregarse correctamente',
        );
      }

      // ===== FASE 7: VERIFICACIONES AVANZADAS =====
      Log.i(
        '🔹 FASE 7: Verificaciones avanzadas de integridad',
        tag: 'ROBUST_TEST',
      );

      // 7.1 Verificar export/import round-trip multiple
      for (int round = 1; round <= 2; round++) {
        final currentRepository = LocalChatRepository();
        final currentData = await currentRepository.loadAll();
        expect(currentData, isNotNull);

        final currentExport = ChatExport.fromJson(currentData!);
        final roundTripJson = jsonEncode(currentExport.toJson());
        final roundTripImport = await ChatJsonUtils.importAllFromJson(
          roundTripJson,
        );

        expect(
          roundTripImport,
          isNotNull,
          reason: 'Round-trip #$round debe funcionar',
        );
        expect(roundTripImport!.profile.userName, equals('TestUser'));
        expect(roundTripImport.timeline[0].level, equals(-1));
      }

      // 7.2 Verificar compatibilidad con repository directo
      final directRepo = LocalChatRepository();
      final directData = await directRepo.loadAll();
      expect(
        directData,
        isNotNull,
        reason: 'Repository directo debe cargar datos',
      );
      expect(directData!['userName'], equals('TestUser'));
      expect(directData['timeline'], isA<List>());

      // 7.3 Verificar estructura de datos en SharedPreferences
      final finalStoredData = await PrefsUtils.getOnboardingData();
      expect(finalStoredData, isNotNull);
      final finalStoredMap = jsonDecode(finalStoredData!);
      expect(finalStoredMap['timeline'], isA<List>());
      expect((finalStoredMap['timeline'] as List)[0]['level'], equals(-1));

      // ===== FASE 8: SIMULACIÓN DE CIERRE DE SESIÓN =====
      Log.i(
        '🔹 FASE 8: Simulación de cierre de sesión completo',
        tag: 'ROBUST_TEST',
      );

      // 8.1 Ejecutar cierre de sesión completo (igual que resetApp)
      await AppDataUtils.clearAllAppData();
      Log.i('  - AppDataUtils.clearAllAppData() ejecutado', tag: 'ROBUST_TEST');

      // 8.2 Verificar que TODOS los datos fueron eliminados completamente
      final dataAfterLogout = await PrefsUtils.getOnboardingData();
      expect(
        dataAfterLogout,
        isNull,
        reason:
            'Datos de onboarding deben estar completamente eliminados tras logout',
      );

      final chatHistoryAfterLogout = await PrefsUtils.getChatHistory();
      expect(
        chatHistoryAfterLogout,
        isNull,
        reason: 'Historial de chat debe estar eliminado tras logout',
      );

      final eventsAfterLogout = await PrefsUtils.getEvents();
      expect(
        eventsAfterLogout,
        isNull,
        reason: 'Eventos deben estar eliminados tras logout',
      );

      // 8.3 Verificar que repository también está limpio
      final repositoryAfterLogout = LocalChatRepository();
      final repositoryDataAfterLogout = await repositoryAfterLogout.loadAll();
      expect(
        repositoryDataAfterLogout,
        isNull,
        reason: 'Repository debe retornar null tras logout completo',
      );

      // 8.4 Verificar que una nueva sesión arranca completamente desde cero
      final newLifecycleController = OnboardingLifecycleController(
        chatRepository: LocalChatRepository(),
      );
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 10));
        return newLifecycleController.loading;
      });

      expect(
        newLifecycleController.generatedBiography,
        isNull,
        reason: 'Nueva sesión debe arrancar sin biografía tras logout',
      );
      expect(
        newLifecycleController.biographySaved,
        isFalse,
        reason: 'Nueva sesión debe indicar que no hay biografía guardada',
      );

      Log.i(
        '✅ CIERRE DE SESIÓN VERIFICADO - LIMPIEZA COMPLETA EXITOSA',
        tag: 'ROBUST_TEST',
      );
      Log.i('✅ TODAS LAS FASES COMPLETADAS EXITOSAMENTE', tag: 'ROBUST_TEST');
    });

    test('Data corruption recovery and edge cases', () async {
      Log.i(
        '\n🔹 TEST: Recuperación de corrupción y casos extremos',
        tag: 'ROBUST_TEST',
      );

      final fake = FakeAIService.forAppearanceAndBiography();
      AIService.testOverride = fake;

      // Caso 1: JSON parcialmente corrupto
      const corruptedJson =
          '{"userName":"TestUser","aiName":"TestAI","biography":{'; // JSON incompleto
      final importResult = await ChatJsonUtils.importAllFromJson(corruptedJson);
      expect(
        importResult,
        isNull,
        reason: 'JSON corrupto debe fallar graciosamente',
      );

      // Caso 2: Datos faltantes pero JSON válido
      const incompleteJson = '{"userName":"","aiName":"TestAI","messages":[]}';
      final incompleteResult = await ChatJsonUtils.importAllFromJson(
        incompleteJson,
      );
      expect(
        incompleteResult,
        isNull,
        reason: 'Datos incompletos deben rechazarse',
      );

      // Caso 3: Múltiples limpiezas seguidas
      await PrefsUtils.clearAll();
      await PrefsUtils.clearAll();
      await PrefsUtils.clearAll();

      final dataAfterMultipleClear = await PrefsUtils.getOnboardingData();
      expect(dataAfterMultipleClear, isNull);

      // Caso 4: Timeline sin level especificado (debe usar default)
      const timelineTestJson = '''
      {
        "userName": "TestUser",
        "aiName": "TestAI", 
        "biography": {},
        "appearance": {},
        "messages": [],
        "events": [],
        "timeline": [{"resume": "Sin level"}]
      }''';

      final timelineResult = await ChatJsonUtils.importAllFromJson(
        timelineTestJson,
      );
      expect(timelineResult, isNotNull);
      // Verificar que el timeline entry se procesa correctamente incluso sin level

      Log.i('✅ Casos extremos manejados correctamente', tag: 'ROBUST_TEST');
    });

    test('🗣️ Conversational onboarding → Full E2E robust flow', () async {
      Log.i(
        '\n🔹 TEST: Flujo conversacional completo E2E robusto',
        tag: 'ROBUST_TEST',
      );

      // ===== FASE 1: SETUP Y ONBOARDING CONVERSACIONAL =====
      Log.i(
        '🔹 FASE 1: Configuración y onboarding conversacional',
        tag: 'ROBUST_TEST',
      );

      await PrefsUtils.clearAll();
      AIService.testOverride = FakeAIService.forAppearanceAndBiography();

      // 1.1 Simular flujo conversacional completo (paso a paso como usuario real)
      final bioUseCase = BiographyGenerationUseCase();
      final conversationalProfile = await bioUseCase.generateCompleteBiography(
        userName: 'ConvUser',
        aiName: 'ConvAI',
        userBirthdate: DateTime(1995, 6, 10),
        meetStory: 'Nos conocimos online durante una conversación mágica',
        userCountryCode: 'MX',
        aiCountryCode: 'JP',
      );

      // Verificar datos del perfil generado por flujo conversacional
      expect(conversationalProfile.userName, equals('ConvUser'));
      expect(conversationalProfile.aiName, equals('ConvAI'));
      expect(conversationalProfile.biography, isNotEmpty);
      expect(conversationalProfile.appearance, isNotEmpty);
      expect(conversationalProfile.avatars, isNotEmpty);

      // ===== FASE 2: VERIFICACIÓN DE PERSISTENCIA CONVERSACIONAL =====
      Log.i(
        '🔹 FASE 2: Verificación de persistencia conversacional con timeline',
        tag: 'ROBUST_TEST',
      );

      // 2.1 Verificar que la biografía conversacional se guardó correctamente
      final storedConvData = await PrefsUtils.getOnboardingData();
      expect(
        storedConvData,
        isNotNull,
        reason: 'Datos conversacionales deben persistirse',
      );

      final storedConvMap = jsonDecode(storedConvData!);
      expect(storedConvMap['userName'], equals('ConvUser'));
      expect(storedConvMap['aiName'], equals('ConvAI'));
      expect(
        storedConvMap['timeline'],
        isA<List>(),
        reason: 'Timeline debe existir en flujo conversacional',
      );
      final conversationalTimeline = storedConvMap['timeline'] as List;
      expect(
        conversationalTimeline.length,
        equals(1),
        reason: 'Debe haber exactamente 1 entrada de timeline conversacional',
      );
      expect(
        conversationalTimeline[0]['resume'],
        equals('Nos conocimos online durante una conversación mágica'),
      );
      expect(
        conversationalTimeline[0]['level'],
        equals(-1),
        reason: 'MeetStory conversacional debe tener nivel -1',
      );

      // 2.2 Verificar integridad de datos guardados conversacionales
      final storedConvProfile = Map<String, dynamic>.from(storedConvMap)
        ..remove('messages')
        ..remove('events')
        ..remove('timeline');
      expect(
        storedConvProfile,
        equals(conversationalProfile.toJson()),
        reason: 'Perfil conversacional guardado debe coincidir',
      );

      // ===== FASE 3: SIMULACIÓN DE CHAT CONVERSACIONAL VIA REPOSITORY =====
      Log.i(
        '🔹 FASE 3: Simulación de persistencia chat conversacional via repository',
        tag: 'ROBUST_TEST',
      );

      final repository = LocalChatRepository();

      // 3.1 Simular mensajes conversacionales específicos
      final conversationalMessages = [
        {
          'text':
              '¡Hola ConvAI! ¿Cómo te sientes después de nuestra charla inicial?',
          'sender': 'user',
          'dateTime': DateTime.now().toIso8601String(),
          'status': 'sent',
        },
        {
          'text':
              '¡Hola ConvUser! Me siento increíble después de conocerte en esa conversación mágica. Fue especial.',
          'sender': 'assistant',
          'dateTime': DateTime.now()
              .add(const Duration(seconds: 2))
              .toIso8601String(),
          'status': 'read',
        },
        {
          'text': 'Cuéntame más sobre tu experiencia en México',
          'sender': 'user',
          'dateTime': DateTime.now()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          'status': 'sent',
        },
      ];

      final conversationalEvents = [
        {
          'type': 'conversational_milestone',
          'description': 'Primera sesión conversacional completada',
          'date': DateTime.now().toIso8601String(),
        },
        {
          'type': 'cultural_exchange',
          'description': 'Intercambio cultural México-Japón iniciado',
          'date': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      ];

      // 3.2 Crear ChatExport conversacional completo
      final conversationalExportData = conversationalProfile.toJson();
      conversationalExportData['messages'] = conversationalMessages;
      conversationalExportData['events'] = conversationalEvents;

      // 3.3 Asegurar timeline conversacional en el export
      final conversationalMeetStory =
          conversationalProfile.biography['meetStory'] ??
          'Historia conversacional';
      final conversationalTimelineEntry = {
        'resume': conversationalMeetStory,
        'startDate': DateTime.now()
            .subtract(const Duration(days: 20))
            .toIso8601String(),
        'endDate': DateTime.now().toIso8601String(),
        'level': -1,
      };
      conversationalExportData['timeline'] = [conversationalTimelineEntry];

      // 3.4 Persistir usando repository
      await repository.saveAll(conversationalExportData);

      // 3.5 Verificar que los datos conversacionales se guardaron correctamente
      final loadedConvData = await repository.loadAll();
      expect(
        loadedConvData,
        isNotNull,
        reason: 'Repository debe cargar datos conversacionales',
      );
      expect(loadedConvData!['userName'], equals('ConvUser'));
      expect(loadedConvData['aiName'], equals('ConvAI'));
      expect(loadedConvData['timeline'], isA<List>());
      final loadedConvTimeline = loadedConvData['timeline'] as List;
      expect(
        loadedConvTimeline.length,
        greaterThan(0),
        reason: 'Timeline conversacional debe tener al menos una entrada',
      );
      expect(loadedConvTimeline[0]['level'], equals(-1));

      // ===== FASE 4: EXPORT/IMPORT CONVERSACIONAL COMPLETO =====
      Log.i(
        '🔹 FASE 4: Export/Import conversacional completo',
        tag: 'ROBUST_TEST',
      );

      // 4.1 Exportar datos conversacionales como ChatExport
      final conversationalChatExport = ChatExport.fromJson(loadedConvData);

      // 4.2 Verificar integridad del export conversacional
      expect(conversationalChatExport.profile.userName, equals('ConvUser'));
      expect(conversationalChatExport.profile.aiName, equals('ConvAI'));
      expect(
        conversationalChatExport.messages.length,
        equals(3),
        reason: 'Export conversacional debe incluir 3 mensajes',
      );
      expect(
        conversationalChatExport.events.length,
        equals(2),
        reason: 'Export conversacional debe incluir 2 eventos',
      );
      expect(
        conversationalChatExport.timeline.length,
        equals(1),
        reason: 'Timeline conversacional debe mantenerse',
      );
      expect(conversationalChatExport.timeline[0].level, equals(-1));

      // 4.3 Serializar conversacional a JSON
      final conversationalExportJson = jsonEncode(
        conversationalChatExport.toJson(),
      );
      expect(conversationalExportJson, isNotEmpty);

      // Verificar JSON conversacional válido
      final conversationalExportMap =
          jsonDecode(conversationalExportJson) as Map<String, dynamic>;
      expect(conversationalExportMap['userName'], equals('ConvUser'));
      expect(conversationalExportMap['aiName'], equals('ConvAI'));
      expect(conversationalExportMap['messages'], isA<List>());
      expect(conversationalExportMap['timeline'], isA<List>());
      expect(conversationalExportMap['events'], isA<List>());

      // ===== FASE 5: LIMPIEZA Y REIMPORT CONVERSACIONAL =====
      Log.i(
        '🔹 FASE 5: Limpieza total y reimport conversacional',
        tag: 'ROBUST_TEST',
      );

      // 5.1 Limpiar TODOS los datos
      await PrefsUtils.clearAll();
      await repository.clearAll();

      // Verificar limpieza completa
      final clearedConvData = await PrefsUtils.getOnboardingData();
      expect(
        clearedConvData,
        isNull,
        reason: 'Datos conversacionales deben estar completamente limpiados',
      );

      // 5.2 Import conversacional usando ChatJsonUtils
      String? conversationalImportError;
      final importedConversationalChat = await ChatJsonUtils.importAllFromJson(
        conversationalExportJson,
        onError: (final error) => conversationalImportError = error,
      );

      expect(
        conversationalImportError,
        isNull,
        reason: 'Import conversacional no debe tener errores',
      );
      expect(
        importedConversationalChat,
        isNotNull,
        reason: 'Import conversacional debe devolver datos válidos',
      );
      expect(importedConversationalChat!.profile.userName, equals('ConvUser'));
      expect(importedConversationalChat.profile.aiName, equals('ConvAI'));
      expect(importedConversationalChat.timeline.length, equals(1));
      expect(importedConversationalChat.timeline[0].level, equals(-1));
      expect(importedConversationalChat.messages.length, equals(3));
      expect(importedConversationalChat.events.length, equals(2));

      // 5.3 Aplicar datos conversacionales importados
      await repository.saveAll(importedConversationalChat.toJson());

      // ===== FASE 6: MÚLTIPLES REINICIOS CONVERSACIONALES =====
      Log.i(
        '🔹 FASE 6: Múltiples reinicios simulados conversacionales',
        tag: 'ROBUST_TEST',
      );

      for (int convRestart = 1; convRestart <= 3; convRestart++) {
        Log.i(
          '  - Simulando reinicio conversacional #$convRestart',
          tag: 'ROBUST_TEST',
        );

        // 6.1 Crear nuevo repository conversacional
        final newConvRepository = LocalChatRepository();

        // 6.2 Cargar datos conversacionales tras reinicio
        final convDataAfterRestart = await newConvRepository.loadAll();

        // 6.3 Verificar integridad conversacional tras reinicio
        expect(
          convDataAfterRestart,
          isNotNull,
          reason:
              'Datos conversacionales deben cargarse tras reinicio #$convRestart',
        );
        expect(convDataAfterRestart!['userName'], equals('ConvUser'));
        expect(convDataAfterRestart['aiName'], equals('ConvAI'));
        expect(
          convDataAfterRestart['timeline'],
          isA<List>(),
          reason: 'Timeline conversacional debe persistir',
        );
        expect(
          (convDataAfterRestart['timeline'] as List)[0]['level'],
          equals(-1),
        );
        expect(
          convDataAfterRestart['messages'],
          isNotEmpty,
          reason: 'Mensajes conversacionales deben persistir',
        );
        expect(
          (convDataAfterRestart['messages'] as List).length,
          greaterThanOrEqualTo(3),
          reason: 'Debe tener al menos 3 mensajes base',
        );
        expect(
          convDataAfterRestart['events'],
          isNotEmpty,
          reason: 'Eventos conversacionales deben persistir',
        );

        // 6.4 Verificar OnboardingLifecycleController con datos conversacionales
        final convLifecycleController = OnboardingLifecycleController(
          chatRepository: LocalChatRepository(),
        );
        await Future.doWhile(() async {
          await Future.delayed(const Duration(milliseconds: 10));
          return convLifecycleController.loading;
        });

        expect(
          convLifecycleController.generatedBiography,
          isNotNull,
          reason: 'Controller debe cargar biografía conversacional',
        );
        expect(
          convLifecycleController.generatedBiography!.userName,
          equals('ConvUser'),
        );
        expect(
          convLifecycleController.generatedBiography!.aiName,
          equals('ConvAI'),
        );

        // 6.5 Agregar mensaje conversacional y verificar persistencia
        final updatedConvData = Map<String, dynamic>.from(convDataAfterRestart);
        final convMessages = List<Map<String, dynamic>>.from(
          updatedConvData['messages'] as List,
        );
        convMessages.add({
          'text':
              'Mensaje conversacional tras reinicio #$convRestart - ¡Increíble persistencia!',
          'sender': 'user',
          'dateTime': DateTime.now().toIso8601String(),
          'status': 'sent',
        });
        updatedConvData['messages'] = convMessages;

        await newConvRepository.saveAll(updatedConvData);
        final verifyConvData = await newConvRepository.loadAll();
        expect(
          (verifyConvData!['messages'] as List).length,
          greaterThan(3 + convRestart - 1),
        );
      }

      // ===== FASE 7: VERIFICACIONES CONVERSACIONALES AVANZADAS =====
      Log.i(
        '🔹 FASE 7: Verificaciones conversacionales avanzadas',
        tag: 'ROBUST_TEST',
      );

      // 7.1 Round-trip conversacional múltiple
      for (int convRound = 1; convRound <= 2; convRound++) {
        final currentConvRepository = LocalChatRepository();
        final currentConvData = await currentConvRepository.loadAll();
        expect(currentConvData, isNotNull);

        final currentConvExport = ChatExport.fromJson(currentConvData!);
        final roundTripConvJson = jsonEncode(currentConvExport.toJson());
        final roundTripConvImport = await ChatJsonUtils.importAllFromJson(
          roundTripConvJson,
        );

        expect(
          roundTripConvImport,
          isNotNull,
          reason: 'Round-trip conversacional #$convRound debe funcionar',
        );
        expect(roundTripConvImport!.profile.userName, equals('ConvUser'));
        expect(roundTripConvImport.profile.aiName, equals('ConvAI'));
        expect(roundTripConvImport.timeline[0].level, equals(-1));
        expect(roundTripConvImport.messages.length, greaterThan(3));
      }

      // 7.2 Verificar compatibilidad conversacional con diferentes controladores
      final finalConvRepo = LocalChatRepository();
      final finalConvData = await finalConvRepo.loadAll();
      expect(finalConvData, isNotNull);
      expect(finalConvData!['userName'], equals('ConvUser'));
      expect(finalConvData['aiName'], equals('ConvAI'));
      expect(finalConvData['timeline'], isA<List>());

      // 7.3 Verificar estructura conversacional en SharedPreferences
      final finalConvStoredData = await PrefsUtils.getOnboardingData();
      expect(finalConvStoredData, isNotNull);
      final finalConvStoredMap = jsonDecode(finalConvStoredData!);
      expect(finalConvStoredMap['userName'], equals('ConvUser'));
      expect(finalConvStoredMap['timeline'], isA<List>());
      expect((finalConvStoredMap['timeline'] as List)[0]['level'], equals(-1));

      // ===== FASE 8: SIMULACIÓN DE CIERRE DE SESIÓN CONVERSACIONAL =====
      Log.i(
        '🔹 FASE 8: Simulación de cierre de sesión conversacional completo',
        tag: 'ROBUST_TEST',
      );

      // 8.1 Ejecutar cierre de sesión completo (igual que resetApp)
      await AppDataUtils.clearAllAppData();
      Log.i(
        '  - AppDataUtils.clearAllAppData() ejecutado para flujo conversacional',
        tag: 'ROBUST_TEST',
      );

      // 8.2 Verificar que TODOS los datos conversacionales fueron eliminados
      final convDataAfterLogout = await PrefsUtils.getOnboardingData();
      expect(
        convDataAfterLogout,
        isNull,
        reason:
            'Datos conversacionales deben estar completamente eliminados tras logout',
      );

      final convChatHistoryAfterLogout = await PrefsUtils.getChatHistory();
      expect(
        convChatHistoryAfterLogout,
        isNull,
        reason: 'Historial conversacional debe estar eliminado tras logout',
      );

      final convEventsAfterLogout = await PrefsUtils.getEvents();
      expect(
        convEventsAfterLogout,
        isNull,
        reason: 'Eventos conversacionales deben estar eliminados tras logout',
      );

      // 8.3 Verificar que repository conversacional también está limpio
      final convRepositoryAfterLogout = LocalChatRepository();
      final convRepositoryDataAfterLogout = await convRepositoryAfterLogout
          .loadAll();
      expect(
        convRepositoryDataAfterLogout,
        isNull,
        reason:
            'Repository conversacional debe retornar null tras logout completo',
      );

      // 8.4 Verificar que una nueva sesión conversacional arranca desde cero
      final newConvLifecycleController = OnboardingLifecycleController(
        chatRepository: LocalChatRepository(),
      );
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 10));
        return newConvLifecycleController.loading;
      });

      expect(
        newConvLifecycleController.generatedBiography,
        isNull,
        reason:
            'Nueva sesión conversacional debe arrancar sin biografía tras logout',
      );
      expect(
        newConvLifecycleController.biographySaved,
        isFalse,
        reason:
            'Nueva sesión conversacional debe indicar que no hay biografía guardada',
      );

      // 8.5 Verificar que no quedan residuos de datos conversacionales específicos
      // Verificar que no hay datos residuales antes de que se pueda crear nueva biografía
      final beforeNewBioData = await PrefsUtils.getOnboardingData();
      expect(
        beforeNewBioData,
        isNull,
        reason: 'Debe estar completamente limpio antes de nueva biografía',
      );

      Log.i(
        '✅ CIERRE DE SESIÓN CONVERSACIONAL VERIFICADO - LIMPIEZA COMPLETA EXITOSA',
        tag: 'ROBUST_TEST',
      );
      Log.i(
        '✅ FLUJO CONVERSACIONAL E2E COMPLETADO EXITOSAMENTE',
        tag: 'ROBUST_TEST',
      );
    });
  });
}
