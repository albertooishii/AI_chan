import 'dart:convert';
import 'dart:io';

import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_utils/prefs_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Mockear SharedPreferences para tests
    PrefsTestUtils.setMockInitialValues();
  });

  test(
    'onboarding+chat persistence -> save/import roundtrip and export JSON',
    () async {
      // Construir un perfil mínimo
      final timeline = [
        TimelineEntry(resume: 'Inicio', startDate: '2020-01-01'),
      ];
      final avatar = AiImage(
        url: 'file://avatar.png',
        seed: 'seed123',
        prompt: 'portrait',
      );
      final profile = AiChanProfile(
        userName: 'Usuario Test',
        aiName: 'AiChan',
        userBirthday: DateTime(1990),
        aiBirthday: DateTime(2024),
        biography: {'short': 'Biografía de prueba'},
        appearance: {'hair': 'negro'},
        timeline: timeline,
        avatars: [avatar],
        events: [
          EventEntry(
            type: 'promesa',
            description: 'Hacer backup',
            date: DateTime.now(),
          ),
        ],
      );

      // Mensajes de ejemplo
      final m1 = Message(
        text: 'Hola',
        sender: MessageSender.user,
        dateTime: DateTime.now(),
      );
      final m2 = Message(
        text: 'Hola',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        isAudio: true,
        audio: AiAudio(
          url: '${Directory.systemTemp.path}/ai_chan/tts.mp3',
          transcript: 'Hola',
          isAutoTts: true,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final events = [
        EventEntry(type: 'cita', description: 'Doctor', date: DateTime.now()),
      ];

      // Usar StorageUtils para guardar (simula import/save)
      final imported = ImportedChat(
        profile: profile,
        messages: [m1, m2],
        events: events,
      );
      await StorageUtils.saveImportedChatToPrefs(imported);

      final prefs = await SharedPreferences.getInstance();
      final bioStr = prefs.getString('onboarding_data');
      expect(bioStr, isNotNull);
      final bioMap = jsonDecode(bioStr!);

      // tryFromJson debe aceptar y devolver un perfil válido
      final parsed = await AiChanProfile.tryFromJson(
        bioMap as Map<String, dynamic>,
      );
      expect(parsed, isNotNull);
      expect(parsed!.userName, equals(profile.userName));

      final hist = prefs.getString('chat_history');
      expect(hist, isNotNull);
      final histList = jsonDecode(hist!) as List<dynamic>;
      expect(histList.length, equals(2));

      // Probar ChatExport roundtrip
      final export = ChatExport(
        profile: profile,
        messages: [m1, m2],
        events: events,
      );
      final map = export.toJson();
      final restored = ChatExport.fromJson(map);
      expect(restored.profile.userName, equals(profile.userName));
      expect(restored.messages.length, equals(2));
      expect(restored.events.length, equals(1));

      // Probar export via BackupUtils (sin repositorio)
      final provider = ChatProvider();
      provider.onboardingData = profile;
      provider.messages = [m1, m2];
      final exportedStr = await BackupUtils.exportChatPartsToJson(
        profile: provider.onboardingData,
        messages: provider.messages,
        events: provider.events,
      );
      final decoded = jsonDecode(exportedStr) as Map<String, dynamic>;
      expect(
        decoded['userName'] ?? decoded['profile']?['userName'],
        equals(profile.userName),
      );
      final messagesList =
          decoded['messages'] ?? (decoded['profile']?['messages']);
      expect((messagesList as List).length, equals(2));
    },
  );

  test(
    'persistence survives reload: loadAll restores onboarding/messages/events',
    () async {
      // Construir un perfil mínimo
      final timeline = [
        TimelineEntry(resume: 'Inicio', startDate: '2020-01-01'),
      ];
      final avatar = AiImage(
        url: 'file://avatar.png',
        seed: 'seed123',
        prompt: 'portrait',
      );
      final profile = AiChanProfile(
        userName: 'Usuario Reload',
        aiName: 'AiChan',
        userBirthday: DateTime(1990),
        aiBirthday: DateTime(2024),
        biography: {'short': 'Biografía recarga'},
        appearance: {'hair': 'negro'},
        timeline: timeline,
        avatars: [avatar],
        events: [
          EventEntry(
            type: 'promesa',
            description: 'Hacer backup',
            date: DateTime.now(),
          ),
        ],
      );

      final m1 = Message(
        text: 'Hola recarga',
        sender: MessageSender.user,
        dateTime: DateTime.now(),
      );
      final m2 = Message(
        text: 'Respuesta',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
      );
      final events = [
        EventEntry(type: 'cita', description: 'Dentista', date: DateTime.now()),
      ];

      final imported = ImportedChat(
        profile: profile,
        messages: [m1, m2],
        events: events,
      );
      await StorageUtils.saveImportedChatToPrefs(imported);

      // Simular recarga: crear un nuevo provider y cargar desde prefs
      final provider = ChatProvider();
      await provider.loadAll();

      expect(provider.onboardingData.userName, equals(profile.userName));
      expect(provider.messages.length, equals(2));
      expect(provider.events.length, equals(1));
    },
  );

  test(
    'ChatJsonUtils.importAllFromJson accepts valid JSON and rejects corrupted',
    () async {
      // Crear perfil y mensajes válidos
      final timeline = [
        TimelineEntry(resume: 'Inicio', startDate: '2020-01-01'),
      ];
      final profile = AiChanProfile(
        userName: 'ImportTest',
        aiName: 'AiChan',
        userBirthday: DateTime(1990),
        aiBirthday: DateTime(2024),
        biography: {'short': 'bio'},
        appearance: {'hair': 'negro'},
        timeline: timeline,
      );

      final m1 = Message(
        text: 'Hola',
        sender: MessageSender.user,
        dateTime: DateTime.now(),
      );
      final m2 = Message(
        text: 'Adios',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
      );
      final events = [
        EventEntry(type: 'cita', description: 'Prueba', date: DateTime.now()),
      ];

      final Map<String, dynamic> goodMap = profile.toJson();
      goodMap['messages'] = [m1.toJson(), m2.toJson()];
      goodMap['events'] = events.map((e) => e.toJson()).toList();

      String? errMsg;
      final importedGood =
          await chat_json_utils.ChatJsonUtils.importAllFromJson(
            jsonEncode(goodMap),
            onError: (e) => errMsg = e,
          );
      expect(errMsg, isNull);
      expect(importedGood, isNotNull);
      expect(importedGood!.profile.userName, equals(profile.userName));

      // Caso: estructura inválida (faltan claves)
      errMsg = null;
      final badStruct = jsonEncode({
        'userName': 'x',
        'aiName': 'y',
        'biography': {},
        'appearance': {},
      });
      final importedBad = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        badStruct,
        onError: (e) => errMsg = e,
      );
      expect(importedBad, isNull);
      expect(errMsg, isNotNull);

      // Caso: JSON malformado
      errMsg = null;
      final importedMalformed =
          await chat_json_utils.ChatJsonUtils.importAllFromJson(
            'not a json',
            onError: (e) => errMsg = e,
          );
      expect(importedMalformed, isNull);
      expect(errMsg, isNotNull);
    },
  );
}
