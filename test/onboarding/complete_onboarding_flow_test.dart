import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_chan/core.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/chat.dart';
import '../test_setup.dart';

void main() {
  group('Complete Onboarding Flow Tests', () {
    setUpAll(() async {
      await initializeTestEnvironment();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrefsUtils.clearAll();
    });

    testWidgets(
      'Complete application lifecycle with onboarding, persistence, restart, logout and reset',
      (WidgetTester tester) async {
        // Verificar estado inicial limpio
        final initialData = await PrefsUtils.getOnboardingData();
        expect(initialData, isNull, reason: 'Estado inicial debe estar limpio');

        // Crear controladores
        final formController = FormOnboardingController();
        final lifecycleController = OnboardingLifecycleController(
          chatRepository: LocalChatRepository(),
        );

        // Crear perfil de prueba
        final testProfile = AiChanProfile(
          userName: 'Ana Sofía',
          aiName: 'AI-chan',
          userBirthdate: DateTime(1998, 5, 15),
          aiBirthdate: DateTime.now(),
          biography: {
            'meetStory':
                'Nos conocimos en una exposición de arte contemporáneo...',
            'personalStory':
                'Ana es una artista freelance que encuentra inspiración...',
            'backgroundInfo': 'Creció en una familia de artistas...',
          },
          appearance: {
            'altura': '1.65m',
            'cabello': 'Castaño con reflejos dorados',
            'ojos': 'Verde esmeralda',
            'estilo': 'Bohemio-chic',
          },
        );

        // Guardar perfil usando PrefsUtils
        await PrefsUtils.setOnboardingData(jsonEncode(testProfile.toJson()));

        // Verificar persistencia
        final storedData = await PrefsUtils.getOnboardingData();
        expect(storedData, isNotNull, reason: 'Perfil debe guardarse');

        final storedProfile = AiChanProfile.fromJson(jsonDecode(storedData!));
        expect(
          storedProfile.userName,
          testProfile.userName,
          reason: 'Nombre debe coincidir',
        );
        expect(
          storedProfile.aiName,
          testProfile.aiName,
          reason: 'Nombre AI debe coincidir',
        );

        // Crear repositorio y mensajes de prueba
        final chatRepo = LocalChatRepository();

        final testMessages = [
          Message(
            text: '¡Hola! Qué gusto conocerte por fin',
            sender: MessageSender.user,
            dateTime: DateTime.now().subtract(const Duration(hours: 2)),
            status: MessageStatus.read,
          ),
          Message(
            text: '¡Hola Ana! El gusto es mío. Me encanta tu energía',
            sender: MessageSender.assistant,
            dateTime: DateTime.now().subtract(
              const Duration(hours: 1, minutes: 59),
            ),
            status: MessageStatus.read,
          ),
        ];

        // Crear y guardar export de prueba
        final chatExport = ChatExport(
          profile: testProfile,
          messages: testMessages,
          events: [],
          timeline: [],
        );

        await chatRepo.saveAll(chatExport.toJson());

        // Verificar que los datos se guardaron
        final savedData = await chatRepo.loadAll();
        expect(
          savedData,
          isNotNull,
          reason: 'Datos deben guardarse en repository',
        );
        expect(
          savedData!['userName'],
          testProfile.userName,
          reason: 'Usuario debe persistir',
        );

        // Simular reinicio de aplicación limpiando controladores
        formController.dispose();
        lifecycleController.dispose();

        // Crear nuevos controladores para simular reinicio
        final newFormController = FormOnboardingController();
        final newLifecycleController = OnboardingLifecycleController(
          chatRepository: LocalChatRepository(),
        );
        final newChatRepo = LocalChatRepository();

        // Verificar que los datos persisten tras "reinicio"
        final restoredData = await PrefsUtils.getOnboardingData();
        expect(
          restoredData,
          isNotNull,
          reason: 'Datos deben persistir tras reinicio',
        );

        final restoredProfile = AiChanProfile.fromJson(
          jsonDecode(restoredData!),
        );
        expect(
          restoredProfile.userName,
          testProfile.userName,
          reason: 'Usuario debe persistir',
        );

        final restoredChatData = await newChatRepo.loadAll();
        expect(
          restoredChatData,
          isNotNull,
          reason: 'Datos de chat deben persistir',
        );

        // Verificar funcionalidad de export/import
        final exportJson = await chatRepo.exportAllToJson(chatExport.toJson());
        expect(exportJson, isNotEmpty, reason: 'Export debe generar JSON');

        // Limpiar todo para simular logout
        await PrefsUtils.clearAll();
        await newChatRepo.clearAll();

        // Verificar que logout limpia todo
        final dataAfterLogout = await PrefsUtils.getOnboardingData();
        expect(
          dataAfterLogout,
          isNull,
          reason: 'Logout debe limpiar datos de onboarding',
        );

        final chatDataAfterLogout = await newChatRepo.loadAll();
        expect(
          chatDataAfterLogout,
          isNull,
          reason: 'Logout debe limpiar datos de chat',
        );

        // Test de import tras logout
        final importedData = await newChatRepo.importAllFromJson(exportJson);
        expect(
          importedData,
          isNotNull,
          reason: 'Import debe funcionar tras logout',
        );

        // Cleanup
        newFormController.dispose();
        newLifecycleController.dispose();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'Data corruption recovery and validation',
      (WidgetTester tester) async {
        // Crear datos corruptos intencionalmente
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('onboarding_data', '{invalid_json}');

        // Verificar que los datos corruptos se detectan correctamente
        final corruptedData = await PrefsUtils.getOnboardingData();
        expect(
          corruptedData,
          '{invalid_json}',
          reason: 'Datos corruptos deben leerse como están',
        );

        // Intentar parsear debería fallar silenciosamente
        try {
          jsonDecode(corruptedData!);
          fail('Parsing de datos corruptos debería fallar');
        } on FormatException catch (e) {
          // Esto es lo esperado
          expect(
            e,
            isA<FormatException>(),
            reason: 'Debe ser error de formato',
          );
        }

        // Limpiar y verificar recuperación
        await PrefsUtils.clearAll();
        final cleanedData = await PrefsUtils.getOnboardingData();
        expect(
          cleanedData,
          isNull,
          reason: 'Datos deben limpiarse correctamente',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'Round-trip export/import data integrity',
      (WidgetTester tester) async {
        final chatRepo = LocalChatRepository();

        // Crear datos de prueba completos
        final testProfile = AiChanProfile(
          userName: 'María Elena',
          aiName: 'AI-chan Test',
          userBirthdate: DateTime(1992, 3, 8),
          aiBirthdate: DateTime.now(),
          biography: {
            'meetStory':
                'Nos conocimos durante una conversación sobre música y arte...',
            'personalStory': 'María Elena es una persona artística...',
            'backgroundInfo': 'Su amor por el arte define su personalidad...',
          },
          appearance: {
            'cabello': 'Negro',
            'ojos': 'Marrones',
            'estilo': 'Elegante y artístico',
          },
        );

        final testMessages = [
          Message(
            text: 'Hola, me gustaría conocerte mejor',
            sender: MessageSender.user,
            dateTime: DateTime.now().subtract(const Duration(minutes: 10)),
            status: MessageStatus.read,
          ),
          Message(
            text: 'Perfecto, cuéntame más sobre ti',
            sender: MessageSender.assistant,
            dateTime: DateTime.now().subtract(const Duration(minutes: 9)),
            status: MessageStatus.read,
          ),
        ];

        final originalExport = ChatExport(
          profile: testProfile,
          messages: testMessages,
          events: [],
          timeline: [],
        );

        // Export -> Import -> Export ciclo completo
        await chatRepo.saveAll(originalExport.toJson());
        final exportJson = await chatRepo.exportAllToJson(
          originalExport.toJson(),
        );

        // Limpiar y re-importar
        await chatRepo.clearAll();
        final importedData = await chatRepo.importAllFromJson(exportJson);
        expect(importedData, isNotNull, reason: 'Import debe funcionar');

        // Verificar integridad de datos
        expect(
          importedData!['userName'],
          testProfile.userName,
          reason: 'Usuario debe coincidir',
        );
        expect(
          importedData['aiName'],
          testProfile.aiName,
          reason: 'AI nombre debe coincidir',
        );

        final messages = importedData['messages'] as List<dynamic>;
        expect(
          messages.length,
          testMessages.length,
          reason: 'Cantidad de mensajes debe coincidir',
        );

        // Segundo ciclo export/import para verificar estabilidad
        final secondExportJson = await chatRepo.exportAllToJson(importedData);
        final secondImportedData = await chatRepo.importAllFromJson(
          secondExportJson,
        );

        expect(
          secondImportedData,
          isNotNull,
          reason: 'Segundo import debe funcionar',
        );
        expect(
          secondImportedData!['userName'],
          testProfile.userName,
          reason: 'Datos deben ser consistentes',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
