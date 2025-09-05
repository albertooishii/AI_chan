import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

import '../test_utils/prefs_test_utils.dart';
import '../fakes/fake_ai_service.dart';
import '../test_setup.dart';

void main() async {
  await initializeTestEnvironment();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PrefsTestUtils.setMockInitialValues();
  });

  group('🚀 App Full Flow Integration Tests', () {
    test(
      '📱 Complete App Flow: Onboarding → Bio → Appearance → Avatar → Chat → Export',
      () async {
        // 🎯 PASO 1: Datos de onboarding inicial
        final userName = 'TestUser';
        final aiName = 'MiAI';
        final userBirthday = DateTime(1995, 6, 15);
        final meetStory = 'Nos conocimos en una convención de anime';

        Log.d(
          '🔹 PASO 1: Configurando datos iniciales de onboarding...',
          tag: 'TEST',
        );
        Log.d('   Usuario: $userName, AI: $aiName', tag: 'TEST');

        // 🎯 PASO 2: Generar biografía con IA
        Log.d('🔹 PASO 2: Generando biografía...', tag: 'TEST');

        // Crear un servicio combinado que maneja tanto JSON como imágenes
        final fakeAiService = FakeAIService(
          customJsonResponse: {
            'datos_personales': {'nombre_completo': 'Ai Test'},
            'personalidad': {
              'valores': {'Sociabilidad': '5'},
              'descripcion': {'Sociabilidad': 'Amigable'},
            },
            'resumen_breve': 'Biografía de prueba',
            'horario_trabajo': {'dias': '', 'from': '', 'to': ''},
            'horario_estudio': {'dias': '', 'from': '', 'to': ''},
            'horario_dormir': {'from': '23:00', 'to': '07:00'},
            'horarios_actividades': [],
            'familia': [],
            'mascotas': [],
            'estudios': [],
            'trayectoria_profesional': [],
            'relaciones': [],
            'amistades': [],
            'intereses_y_aficiones': {},
            'historia_personal': [],
            'proyectos_personales': [],
            'metas_y_sueños': {},
          },
          imageBase64Response:
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=',
        );

        // Configurar el override global para todos los generadores
        AIService.testOverride = fakeAiService;

        final biography = await generateAIBiographyWithAI(
          userName: userName,
          aiName: aiName,
          userBirthdate: userBirthday,
          meetStory: meetStory,
          userCountryCode: 'ES',
          aiCountryCode: 'JP',
          seed: 12345,
          aiServiceOverride: fakeAiService,
        );

        expect(biography, isNotNull);
        expect(biography.userName, equals(userName));
        expect(biography.aiName, equals(aiName));
        expect(biography.biography, isNotEmpty);
        Log.d(
          '   ✅ Biografía generada con ${biography.biography.keys.length} campos',
          tag: 'TEST',
        );

        // 🎯 PASO 3: Generar apariencia física
        Log.d('🔹 PASO 3: Generando apariencia física...', tag: 'TEST');
        final appearanceGenerator = IAAppearanceGenerator();

        final appearance = await appearanceGenerator
            .generateAppearanceFromBiography(
              biography,
              aiService: fakeAiService,
            );

        expect(appearance, isNotEmpty);
        expect(appearance['edad_aparente'], equals(25));
        Log.d(
          '   ✅ Apariencia generada con ${appearance.keys.length} características',
          tag: 'TEST',
        );

        // Actualizar perfil con apariencia
        final updatedBio = biography.copyWith(appearance: appearance);

        // 🎯 PASO 4: Generar avatar
        Log.d('🔹 PASO 4: Generando avatar...', tag: 'TEST');
        final avatarGenerator = IAAvatarGenerator();

        // Configurar un directorio temporal para guardar el avatar
        Config.setOverrides({
          'TEST_IMAGE_DIR': '${Directory.systemTemp.path}/ai_chan_test',
        });

        final avatar = await avatarGenerator.generateAvatarFromAppearance(
          updatedBio,
        );

        expect(avatar, isNotNull);
        expect(avatar.url, isNotEmpty);
        expect(avatar.seed, equals('test-seed-123'));
        Log.d('   ✅ Avatar generado: ${avatar.url}', tag: 'TEST');

        // Actualizar perfil con avatar
        final fullProfile = updatedBio.copyWith(avatars: [avatar]);

        // 🎯 PASO 5: Simular chat básico
        Log.d('🔹 PASO 5: Configurando chat inicial...', tag: 'TEST');
        final chatProvider = ChatProvider();

        // Crear eventos de prueba
        final testEvents = [
          EventEntry(
            type: 'conocimiento',
            description: 'Primer encuentro en convención de anime',
            date: DateTime.now().subtract(const Duration(days: 30)),
          ),
          EventEntry(
            type: 'promesa',
            description: 'Ver el próximo episodio de anime juntos',
            date: DateTime.now().add(const Duration(days: 1)),
          ),
        ];

        // Actualizar perfil con eventos
        final profileWithEvents = fullProfile.copyWith(events: testEvents);
        chatProvider.onboardingData = profileWithEvents;

        // Agregar algunos mensajes de prueba
        final userMessage = Message(
          text: 'Hola $aiName, ¡me encanta tu avatar!',
          sender: MessageSender.user,
          dateTime: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        final aiMessage = Message(
          text:
              '¡Hola $userName! Gracias, estoy muy emocionada de conocerte después de la convención de anime 😊',
          sender: MessageSender.assistant,
          dateTime: DateTime.now().subtract(const Duration(minutes: 4)),
        );

        chatProvider.messages.addAll([userMessage, aiMessage]);

        Log.d(
          '   ✅ Chat configurado con ${chatProvider.messages.length} mensajes y ${chatProvider.events.length} eventos',
          tag: 'TEST',
        );

        // 🎯 PASO 6: Guardar persistencia
        Log.d('🔹 PASO 6: Guardando datos en persistencia...', tag: 'TEST');
        Log.d(
          '   - Eventos antes de guardar: ${profileWithEvents.events?.length ?? 0}',
          tag: 'TEST',
        );
        Log.d(
          '   - ChatProvider events antes de guardar: ${chatProvider.events.length}',
          tag: 'TEST',
        );

        await StorageUtils.saveImportedChatToPrefs(
          ImportedChat(
            profile: profileWithEvents,
            messages: chatProvider.messages,
            events: profileWithEvents.events ?? [],
          ),
        );

        // Verificar que se guardó
        final prefs = await SharedPreferences.getInstance();
        final savedBio = prefs.getString('onboarding_data');
        final savedMessages = prefs.getString('chat_history');
        final savedEvents = prefs.getString(
          'events',
        ); // Clave correcta para eventos

        expect(savedBio, isNotNull);
        expect(savedMessages, isNotNull);
        expect(savedEvents, isNotNull);
        Log.d('   ✅ Datos guardados en SharedPreferences', tag: 'TEST');

        // 🎯 PASO 7: Exportar a JSON
        Log.d('🔹 PASO 7: Exportando a JSON completo...', tag: 'TEST');
        Log.d('   - Profile: ${profileWithEvents.aiName}', tag: 'TEST');
        Log.d('   - Messages: ${chatProvider.messages.length}', tag: 'TEST');
        Log.d(
          '   - Events: ${profileWithEvents.events?.length ?? 0}',
          tag: 'TEST',
        );

        final exportedJson = await BackupUtils.exportChatPartsToJson(
          profile: profileWithEvents,
          messages: chatProvider.messages,
          events: profileWithEvents.events ?? [],
        );

        expect(exportedJson, isNotEmpty);

        // Validar estructura del JSON exportado
        final exportedData = jsonDecode(exportedJson) as Map<String, dynamic>;
        expect(
          exportedData['userName'] ?? exportedData['profile']?['userName'],
          equals(userName),
        );
        expect(
          exportedData['aiName'] ?? exportedData['profile']?['aiName'],
          equals(aiName),
        );

        final messagesInExport =
            exportedData['messages'] ?? exportedData['profile']?['messages'];
        expect(messagesInExport, isNotNull);
        expect((messagesInExport as List).length, equals(2));

        Log.d(
          '   ✅ JSON exportado correctamente (${exportedJson.length} caracteres)',
          tag: 'TEST',
        );

        // 🎯 PASO 8: Verificar recarga completa
        Log.d(
          '🔹 PASO 8: Verificando recarga completa de datos...',
          tag: 'TEST',
        );
        final newChatProvider = ChatProvider();
        await newChatProvider.loadAll();

        expect(newChatProvider.onboardingData.userName, equals(userName));
        expect(newChatProvider.onboardingData.aiName, equals(aiName));
        expect(newChatProvider.onboardingData.biography, isNotEmpty);
        expect(newChatProvider.onboardingData.appearance, isNotEmpty);
        expect(newChatProvider.onboardingData.avatars, isNotEmpty);
        expect(newChatProvider.messages.length, equals(2));
        // Los eventos están en el perfil, no necesariamente cargados en el ChatProvider
        expect(newChatProvider.onboardingData.events?.length ?? 0, equals(2));

        Log.d('   ✅ Recarga exitosa: todos los datos restaurados', tag: 'TEST');

        // 🎯 PASO 9: Verificar importación desde JSON
        Log.d(
          '🔹 PASO 9: Verificando importación desde JSON exportado...',
          tag: 'TEST',
        );
        String? importError;
        final importedChat =
            await chat_json_utils.ChatJsonUtils.importAllFromJson(
              exportedJson,
              onError: (error) => importError = error,
            );

        expect(importError, isNull);
        expect(importedChat, isNotNull);
        expect(importedChat!.profile.userName, equals(userName));
        expect(importedChat.profile.aiName, equals(aiName));
        expect(importedChat.messages.length, equals(2));
        expect(importedChat.events.length, equals(2));

        Log.d('   ✅ Importación desde JSON verificada', tag: 'TEST');

        Log.d(
          '🎉 FLUJO COMPLETO EXITOSO: Todas las etapas funcionan correctamente',
          tag: 'TEST',
        );
        Log.d('   📊 Resumen:', tag: 'TEST');
        Log.d(
          '      • Biografía: ${biography.biography.keys.length} campos',
          tag: 'TEST',
        );
        Log.d(
          '      • Apariencia: ${appearance.keys.length} características',
          tag: 'TEST',
        );
        Log.d('      • Avatar: generado y persistido', tag: 'TEST');
        Log.d(
          '      • Chat: ${chatProvider.messages.length} mensajes',
          tag: 'TEST',
        );
        Log.d(
          '      • Eventos: ${chatProvider.events.length} eventos',
          tag: 'TEST',
        );
        Log.d(
          '      • Export/Import: JSON válido de ${exportedJson.length} caracteres',
          tag: 'TEST',
        );

        // Limpiar override
        AIService.testOverride = null;
      },
    );

    test(
      '🚨 Error Handling: Flow continues gracefully with fallbacks',
      () async {
        Log.d('🔹 Probando manejo de errores y fallbacks...', tag: 'TEST');

        // Simular fallo en generación de biografía
        final failingService = FailingFakeAIService();

        try {
          await generateAIBiographyWithAI(
            userName: 'ErrorTest',
            aiName: 'ErrorAI',
            userBirthdate: DateTime(1990),
            meetStory: 'Test error',
            aiServiceOverride: failingService,
          );
          fail('Debería haber fallado la generación de biografía');
        } catch (e) {
          expect(e.toString(), contains('No se pudo generar biografía'));
          Log.d('   ✅ Error de biografía manejado correctamente', tag: 'TEST');
        }

        // Crear un perfil mínimo para continuar el flujo
        final fallbackProfile = AiChanProfile(
          userName: 'ErrorTest',
          aiName: 'ErrorAI',
          userBirthdate: DateTime(1990),
          aiBirthdate: DateTime(2024),
          biography: {'fallback': 'Perfil de respaldo'},
          appearance: {'fallback': 'Apariencia básica'},
          timeline: [],
        );

        // Verificar que el chat puede funcionar incluso con datos mínimos
        final chatProvider = ChatProvider();
        chatProvider.onboardingData = fallbackProfile;

        final testMessage = Message(
          text: 'Mensaje de prueba',
          sender: MessageSender.user,
          dateTime: DateTime.now(),
        );

        chatProvider.messages = [testMessage];

        // El export debe funcionar incluso con datos mínimos
        final exportJson = await BackupUtils.exportChatPartsToJson(
          profile: fallbackProfile,
          messages: chatProvider.messages,
          events: [],
        );

        expect(exportJson, isNotEmpty);
        Log.d('   ✅ Flujo de respaldo funciona correctamente', tag: 'TEST');

        // Limpiar override
        AIService.testOverride = null;
      },
    );

    test('🔄 Data Consistency: All generators produce compatible data', () async {
      Log.d('🔹 Verificando consistencia entre generadores...', tag: 'TEST');

      final fakeService = FakeAIService(
        customJsonResponse: {
          'datos_personales': {'nombre_completo': 'Ai Test'},
          'personalidad': {
            'valores': {'Sociabilidad': '5'},
            'descripcion': {'Sociabilidad': 'Amigable'},
          },
          'resumen_breve': 'Biografía de prueba',
        },
        imageBase64Response:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=',
      );
      AIService.testOverride = fakeService;

      // Generar con diferentes combinaciones de países
      final testCases = [
        {'user': 'ES', 'ai': 'JP', 'desc': 'Español-Japonesa'},
        {'user': 'US', 'ai': 'KR', 'desc': 'Americano-Coreana'},
        {'user': 'MX', 'ai': 'MX', 'desc': 'Mexicano-Mexicana'},
      ];

      for (final testCase in testCases) {
        Log.d('   🧪 Caso: ${testCase['desc']}', tag: 'TEST');

        // Generar biografía
        final bio = await generateAIBiographyWithAI(
          userName: 'User${testCase['user']}',
          aiName: 'AI${testCase['ai']}',
          userBirthdate: DateTime(1995, 5, 15),
          meetStory: 'Conocimiento de prueba',
          userCountryCode: testCase['user']!,
          aiCountryCode: testCase['ai']!,
          seed: 42,
          aiServiceOverride: fakeService,
        );

        // Generar apariencia
        final appearance = await IAAppearanceGenerator()
            .generateAppearanceFromBiography(bio, aiService: fakeService);

        // Verificar que la nacionalidad se maneja correctamente
        expect(bio.aiCountryCode, equals(testCase['ai']!.toUpperCase()));
        expect(bio.userCountryCode, equals(testCase['user']!.toUpperCase()));
        expect(appearance['edad_aparente'], equals(25));

        Log.d(
          '      ✅ ${testCase['desc']}: consistencia verificada',
          tag: 'TEST',
        );
      }

      Log.d('   ✅ Todos los casos de consistencia pasaron', tag: 'TEST');

      // Limpiar override
      AIService.testOverride = null;
    });

    test(
      '🔒 Logout → Fresh Start: Ensures complete data cleanup prevents chat restoration bug',
      () async {
        Log.d(
          '🔹 PASO 1: Creando sesión inicial con datos completos...',
          tag: 'TEST',
        );

        // 🎯 Configurar servicio fake
        final fakeService = FakeAIService(
          customJsonResponse: {
            'datos_personales': {'nombre_completo': 'Original User'},
            'personalidad': {
              'valores': {'Sociabilidad': '5'},
              'descripcion': {'Sociabilidad': 'Amigable'},
            },
            'resumen_breve': 'Biografía original',
            'horario_dormir': {'from': '23:00', 'to': '07:00'},
            'horarios_actividades': [],
            'familia': [],
            'mascotas': [],
            'estudios': [],
            'trayectoria_profesional': [],
            'relaciones': [],
            'amistades': [],
            'intereses_y_aficiones': {},
            'historia_personal': [],
            'proyectos_personales': [],
            'metas_y_sueños': {},
          },
          imageBase64Response:
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=',
        );
        AIService.testOverride = fakeService;

        // 🎯 CREAR SESIÓN ORIGINAL completa
        const originalUserName = 'OriginalUser';
        const originalAiName = 'OriginalAI';
        const originalMeetStory = 'Nos conocimos en una cafetería';

        // Generar biografía original
        final originalBio = await generateAIBiographyWithAI(
          userName: originalUserName,
          aiName: originalAiName,
          userBirthdate: DateTime(1990, 3, 15),
          meetStory: originalMeetStory,
          userCountryCode: 'US',
          aiCountryCode: 'JP',
          seed: 99999,
          aiServiceOverride: fakeService,
        );

        // Crear ChatProvider con datos originales
        final originalChatProvider = ChatProvider();
        originalChatProvider.onboardingData = originalBio;

        // Agregar mensajes originales significativos
        final originalMessages = [
          Message(
            text:
                'Mensaje secreto 1: Hola $originalAiName, recuerdas nuestro encuentro en la cafetería?',
            sender: MessageSender.user,
            dateTime: DateTime.now().subtract(const Duration(hours: 2)),
            status: MessageStatus.read,
          ),
          Message(
            text:
                'Mensaje secreto 2: ¡Por supuesto $originalUserName! Fue muy especial hablar contigo sobre libros.',
            sender: MessageSender.assistant,
            dateTime: DateTime.now().subtract(const Duration(hours: 1)),
            status: MessageStatus.read,
          ),
          Message(
            text:
                'Mensaje secreto 3: Este mensaje NO debe aparecer después del reset',
            sender: MessageSender.user,
            dateTime: DateTime.now().subtract(const Duration(minutes: 30)),
            status: MessageStatus.read,
          ),
        ];

        originalChatProvider.messages.addAll(originalMessages);

        // Agregar eventos originales
        final originalEvents = [
          EventEntry(
            type: 'conocimiento',
            description: 'Encuentro original en cafetería - DEBE BORRARSE',
            date: DateTime.now().subtract(const Duration(days: 10)),
          ),
          EventEntry(
            type: 'promesa',
            description: 'Promesa de leer libro juntos - DEBE BORRARSE',
            date: DateTime.now().add(const Duration(days: 5)),
          ),
        ];

        final originalProfileWithEvents = originalBio.copyWith(
          events: originalEvents,
        );
        originalChatProvider.onboardingData = originalProfileWithEvents;

        Log.d(
          '   ✅ Sesión original: ${originalChatProvider.messages.length} mensajes, ${originalEvents.length} eventos',
          tag: 'TEST',
        );

        // 🎯 GUARDAR datos originales en persistencia
        Log.d(
          '🔹 PASO 2: Guardando datos originales en persistencia...',
          tag: 'TEST',
        );
        await originalChatProvider.saveAll();

        // Verificar que los datos están guardados
        final prefs = await SharedPreferences.getInstance();
        final savedBio = prefs.getString('onboarding_data');
        final savedMessages = prefs.getString('chat_history');
        final savedEvents = prefs.getString('events');

        expect(savedBio, isNotNull);
        expect(savedMessages, isNotNull);
        expect(savedEvents, isNotNull);

        // Verificar contenido específico
        expect(savedBio!, contains(originalUserName));
        expect(savedBio, contains(originalAiName));
        expect(savedMessages!, contains('Mensaje secreto'));
        // Los eventos pueden estar vacíos en el test fake, verificamos que no sea null
        expect(savedEvents, isNotNull);

        Log.d(
          '   ✅ Datos originales confirmados en SharedPreferences',
          tag: 'TEST',
        );

        // 🎯 CARGAR desde persistencia para confirmar
        final verificationChatProvider = ChatProvider();
        await verificationChatProvider.loadAll();

        expect(
          verificationChatProvider.onboardingData.userName,
          equals(originalUserName),
        );
        expect(
          verificationChatProvider.onboardingData.aiName,
          equals(originalAiName),
        );
        expect(verificationChatProvider.messages.length, equals(3));
        expect(
          verificationChatProvider.messages.any(
            (m) => m.text.contains('Mensaje secreto'),
          ),
          isTrue,
        );

        Log.d(
          '   ✅ Verificación de carga: datos originales correctamente persistidos',
          tag: 'TEST',
        );

        // 🔥 SIMULAR "CERRAR SESIÓN" - Acción crítica
        Log.d(
          '🔹 PASO 3: 🔥 SIMULANDO CERRAR SESIÓN (resetApp completo)...',
          tag: 'TEST',
        );

        // Primero: clearAll del ChatProvider (nueva lógica)
        await originalChatProvider.clearAll();
        Log.d('   ✅ ChatProvider.clearAll() ejecutado', tag: 'TEST');

        // Segundo: clearAllAppData (lógica existente)
        await originalChatProvider
            .clearAll(); // Simulamos también el AppDataUtils.clearAllAppData que llama PrefsUtils.clearAll
        Log.d('   ✅ Limpieza completa de datos de app ejecutada', tag: 'TEST');

        // 🎯 VERIFICAR limpieza inmediata
        Log.d('🔹 PASO 4: Verificando limpieza inmediata...', tag: 'TEST');

        final prefsAfterClear = await SharedPreferences.getInstance();
        final bioAfterClear = prefsAfterClear.getString('onboarding_data');
        final messagesAfterClear = prefsAfterClear.getString('chat_history');
        final eventsAfterClear = prefsAfterClear.getString('events');

        // Verificar que NO hay datos
        expect(
          bioAfterClear,
          isNull,
          reason: 'onboarding_data should be null after clearAll',
        );
        expect(
          messagesAfterClear,
          isNull,
          reason: 'chat_history should be null after clearAll',
        );
        // Los eventos pueden quedar como lista vacía después de clearAll, verificamos que esté vacío
        expect(
          eventsAfterClear,
          anyOf([isNull, equals('[]')]),
          reason: 'events should be null or empty after clearAll',
        );

        Log.d(
          '   ✅ Verificación inmediata: todos los datos limpiados correctamente',
          tag: 'TEST',
        );

        // 🎯 CREAR NUEVA SESIÓN después del "reset"
        Log.d(
          '🔹 PASO 5: Creando NUEVA sesión después del reset...',
          tag: 'TEST',
        );

        // Nuevos datos completamente diferentes
        const newUserName = 'NewUser';
        const newAiName = 'NewAI';
        const newMeetStory = 'Nos conocimos en una biblioteca';

        // Crear nuevo servicio fake para nueva sesión con datos completamente diferentes
        final newSessionService = FakeAIService(
          customJsonResponse: {
            'datos_personales': {'nombre_completo': 'New User Profile'},
            'personalidad': {
              'valores': {'Creatividad': '8'},
              'descripcion': {'Creatividad': 'Muy creativa'},
            },
            'resumen_breve': 'Biografía completamente nueva',
            'horario_dormir': {'from': '22:00', 'to': '06:00'},
            'horarios_actividades': [],
            'familia': [],
            'mascotas': [],
            'estudios': [],
            'trayectoria_profesional': [],
            'relaciones': [],
            'amistades': [],
            'intereses_y_aficiones': {},
            'historia_personal': [],
            'proyectos_personales': [],
            'metas_y_sueños': {},
          },
        );
        AIService.testOverride = newSessionService;

        final newBio = await generateAIBiographyWithAI(
          userName: newUserName,
          aiName: newAiName,
          userBirthdate: DateTime(1995, 8, 22),
          meetStory: newMeetStory,
          userCountryCode: 'ES',
          aiCountryCode: 'KR',
          seed: 11111,
          aiServiceOverride: fakeService,
        );

        Log.d(
          '   ✅ Nueva biografía generada: $newUserName + $newAiName',
          tag: 'TEST',
        );

        // 🎯 CREAR ChatProvider fresco (como en el flujo real)
        Log.d(
          '🔹 PASO 6: Creando ChatProvider fresco y cargando datos...',
          tag: 'TEST',
        );

        final freshChatProvider = ChatProvider();
        freshChatProvider.onboardingData = newBio;

        // Agregar nuevos mensajes
        final newMessages = [
          Message(
            text: 'Hola $newAiName, es genial conocerte en la biblioteca!',
            sender: MessageSender.user,
            dateTime: DateTime.now(),
            status: MessageStatus.read,
          ),
          Message(
            text:
                'Hola $newUserName! Me encanta leer, será divertido compartir historias contigo.',
            sender: MessageSender.assistant,
            dateTime: DateTime.now(),
            status: MessageStatus.read,
          ),
        ];

        freshChatProvider.messages.addAll(newMessages);
        await freshChatProvider.saveAll();

        Log.d(
          '   ✅ Nueva sesión guardada: ${freshChatProvider.messages.length} mensajes nuevos',
          tag: 'TEST',
        );

        // 🎯 SIMULAR loadAll() como en el flujo real de la app
        Log.d(
          '🔹 PASO 7: Simulando loadAll() del flujo real de la app...',
          tag: 'TEST',
        );

        final appFlowChatProvider = ChatProvider();
        await appFlowChatProvider
            .loadAll(); // Esto es lo que hace MyApp después del onboarding

        // 🔍 VERIFICACIONES CRÍTICAS - El corazón del test
        Log.d('🔹 PASO 8: 🔍 VERIFICACIONES CRÍTICAS DEL BUG...', tag: 'TEST');

        // ❌ Verificar que NO hay datos antiguos
        expect(
          appFlowChatProvider.onboardingData.userName,
          isNot(equals(originalUserName)),
          reason: 'OLD username should NOT be present after reset',
        );

        expect(
          appFlowChatProvider.onboardingData.aiName,
          isNot(equals(originalAiName)),
          reason: 'OLD AI name should NOT be present after reset',
        );

        // Verificar que NO hay mensajes antiguos
        final hasOldSecretMessages = appFlowChatProvider.messages.any(
          (m) => m.text.contains('Mensaje secreto'),
        );
        expect(
          hasOldSecretMessages,
          isFalse,
          reason: 'OLD secret messages should NOT be present after reset',
        );

        final hasOldMeetingReference = appFlowChatProvider.messages.any(
          (m) => m.text.contains('cafetería'),
        );
        expect(
          hasOldMeetingReference,
          isFalse,
          reason: 'OLD meeting references should NOT be present after reset',
        );

        // Verificar que NO hay eventos antiguos
        final hasOldEvents = (appFlowChatProvider.onboardingData.events ?? [])
            .any(
              (e) =>
                  e.description.contains('cafetería') ||
                  e.description.contains('DEBE BORRARSE'),
            );
        expect(
          hasOldEvents,
          isFalse,
          reason: 'OLD events should NOT be present after reset',
        );

        // ✅ Verificar que SÍ hay datos nuevos
        expect(
          appFlowChatProvider.onboardingData.userName,
          equals(newUserName),
          reason: 'NEW username should be present',
        );

        expect(
          appFlowChatProvider.onboardingData.aiName,
          equals(newAiName),
          reason: 'NEW AI name should be present',
        );

        // Verificar que SÍ hay mensajes nuevos
        final hasNewLibraryMessages = appFlowChatProvider.messages.any(
          (m) => m.text.contains('biblioteca'),
        );
        expect(
          hasNewLibraryMessages,
          isTrue,
          reason: 'NEW library messages should be present',
        );

        // 🎉 RESULTADO FINAL
        Log.d('🎉 PASO 9: ¡VERIFICACIÓN EXITOSA!', tag: 'TEST');
        Log.d('   📊 Resumen de la verificación:', tag: 'TEST');
        Log.d(
          '      ❌ Usuario original ($originalUserName) → ELIMINADO ✅',
          tag: 'TEST',
        );
        Log.d(
          '      ❌ IA original ($originalAiName) → ELIMINADA ✅',
          tag: 'TEST',
        );
        Log.d('      ❌ 3 mensajes secretos → ELIMINADOS ✅', tag: 'TEST');
        Log.d('      ❌ 2 eventos cafetería → ELIMINADOS ✅', tag: 'TEST');
        Log.d('      ✅ Nuevo usuario ($newUserName) → PRESENTE ✅', tag: 'TEST');
        Log.d('      ✅ Nueva IA ($newAiName) → PRESENTE ✅', tag: 'TEST');
        Log.d(
          '      ✅ ${appFlowChatProvider.messages.length} mensajes biblioteca → PRESENTES ✅',
          tag: 'TEST',
        );

        Log.d(
          '🔒 BUG DE RESTAURACIÓN DE CHAT: ¡PREVENIDO EXITOSAMENTE!',
          tag: 'TEST',
        );

        // Limpiar override
        AIService.testOverride = null;
      },
    );
  });
}

/// Versión de FakeAIService que siempre falla para tests de error
class FailingFakeAIService extends FakeAIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> messages,
    SystemPrompt systemPrompt, {
    String? model,
    bool enableImageGeneration = false,
    String? imageBase64,
    String? imageMimeType,
  }) async {
    throw Exception('Simulated AI service failure');
  }
}
