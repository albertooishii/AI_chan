import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/models.dart';

void main() {
  test('AiChanProfile toJson/fromJson roundtrip', () {
    final profile = AiChanProfile(
      biography: {'resumen_breve': 'Una chica interesante.'},
      userName: 'UsuarioTest',
      aiName: 'AiTest',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2000, 5, 10),
      appearance: {'seed': 42},
      timeline: [],
    );

    final json = profile.toJson();
    final encoded = jsonEncode(json);
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final restored = AiChanProfile.fromJson(decoded);

    expect(restored.aiName, equals(profile.aiName));
    expect(restored.userName, equals(profile.userName));
    expect(
      restored.biography['resumen_breve'],
      equals('Una chica interesante.'),
    );
  });
}
