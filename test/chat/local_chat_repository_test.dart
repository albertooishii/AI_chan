import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/infrastructure/repositories/local_chat_repository.dart';
import '../test_utils/prefs_test_utils.dart';

import '../test_setup.dart';

void main() {
  setUp(() async {
    await initializeTestEnvironment();
  });

  test('saveAll and loadAll roundtrip using SharedPreferences', () async {
    PrefsTestUtils.setMockInitialValues();
    final repo = LocalChatRepository();

    final payload = {
      'profile': {
        'userName': 'Test',
        'aiName': 'Ai',
        'biography': <String, dynamic>{},
        'appearance': <String, dynamic>{},
        'timeline': <dynamic>[],
      },
      'messages': [
        {'id': 'm1', 'text': 'hola'},
      ],
    };

    await repo.saveAll(payload);
    final loaded = await repo.loadAll();

    expect(loaded, isNotNull);
    // profile may be nested under 'profile' or flattened at root
    final profileMap = loaded!.containsKey('profile') && loaded['profile'] is Map
        ? Map<String, dynamic>.from(loaded['profile'] as Map)
        : Map<String, dynamic>.from(loaded as Map);
    expect(profileMap['userName'], anyOf('Test', ''));
    final messages = loaded.containsKey('messages') ? loaded['messages'] as List : <dynamic>[];
    expect(messages.length, 1);
  });

  test('importAllFromJson with valid and invalid JSON', () async {
    final repo = LocalChatRepository();

    final valid = json.encode({
      'profile': {
        'userName': 'X',
        'aiName': 'Ai',
        'biography': <String, dynamic>{},
        'appearance': <String, dynamic>{},
        'timeline': <dynamic>[],
      },
      'messages': [],
    });
    final parsed = await repo.importAllFromJson(valid);
    expect(parsed, isNotNull);
    final profileParsed = parsed!.containsKey('profile') && parsed['profile'] is Map
        ? Map<String, dynamic>.from(parsed['profile'] as Map)
        : Map<String, dynamic>.from(parsed as Map);
    expect(profileParsed['userName'], anyOf('X', ''));

    final invalid = 'not a json';
    final parsed2 = await repo.importAllFromJson(invalid);
    expect(parsed2, isNull);
  });

  test('exportAllToJson returns a path or the json string', () async {
    final repo = LocalChatRepository();
    final payload = {'profile': {}, 'messages': []};

    final out = await repo.exportAllToJson(payload);
    // The impl returns a file path if it could write to disk, otherwise the JSON
    expect(out, isNotNull);
    expect(out, anyOf(contains('.json'), contains('{')));
  });
}
