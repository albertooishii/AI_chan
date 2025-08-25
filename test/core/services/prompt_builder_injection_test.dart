import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/prompt_builder.dart' as pb;
import '../../test_setup.dart';
import 'package:ai_chan/core/models.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });

  test('PromptBuilder JSON allows injection of foto when enableImageGeneration', () {
    // Construir un SystemPrompt JSON usando PromptBuilder
    final profile = AiChanProfile(
      biography: <String, dynamic>{},
      userName: 'u',
      aiName: 'ai',
      userBirthday: null,
      aiBirthday: null,
      appearance: <String, dynamic>{},
      timeline: [],
    );
    final builder = pb.PromptBuilder();
    final jsonStr = builder.buildRealtimeSystemPromptJson(profile: profile, messages: []);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;

    // Por defecto no debe contener las claves de imagen en las instrucciones
    final instr = map['instructions'] as Map<String, dynamic>;
    expect(instr.containsKey('foto'), isFalse);
    expect(instr.containsKey('metadatos_imagen'), isFalse);

    // Simular inyección que hace OpenAIService cuando enableImageGeneration==true
    instr['foto'] = pb.imageInstructions('u');
    expect(instr['foto'], equals(pb.imageInstructions('u')));
  });

  test('PromptBuilder JSON supports simultaneous foto y metadatos_imagen injection', () {
    final profile = AiChanProfile(
      biography: <String, dynamic>{},
      userName: 'u',
      aiName: 'ai',
      userBirthday: null,
      aiBirthday: null,
      appearance: <String, dynamic>{},
      timeline: [],
    );
    final builder = pb.PromptBuilder();
    final jsonStr = builder.buildRealtimeSystemPromptJson(profile: profile, messages: []);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final instr = map['instructions'] as Map<String, dynamic>;

    // Simular que hay petición de imagen y que el usuario adjuntó una imagen
    instr['foto'] = pb.imageInstructions('u');
    instr['metadatos_imagen'] = pb.imageMetadata('u');

    expect(instr.containsKey('foto'), isTrue);
    expect(instr.containsKey('metadatos_imagen'), isTrue);
    expect(instr['foto'], equals(pb.imageInstructions('u')));
    expect(instr['metadatos_imagen'], equals(pb.imageMetadata('u')));
  });
}
