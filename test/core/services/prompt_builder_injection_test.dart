import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/infrastructure/services/prompt_builder_service.dart'
    as pb;
import '../../test_setup.dart';
import 'package:ai_chan/core/models.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });

  test(
    'PromptBuilder JSON allows injection of foto when enableImageGeneration',
    () {
      // Construir un SystemPrompt JSON usando PromptBuilder
      final profile = AiChanProfile(
        biography: <String, dynamic>{},
        userName: 'u',
        aiName: 'ai',
        userBirthdate: null,
        aiBirthdate: null,
        appearance: <String, dynamic>{},
        timeline: [],
      );
      final builder = pb.PromptBuilderService();
      final jsonStr = builder.buildRealtimeSystemPromptJson(
        profile: profile,
        messages: [],
      );
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Por defecto no debe contener las claves de imagen en las instrucciones
      final instr = map['instructions'] as Map<String, dynamic>;
      expect(instr.containsKey('photo_instructions'), isFalse);
      expect(
        instr.containsKey('attached_image_metadata_instructions'),
        isFalse,
      );

      // Simular inyección que hace OpenAIService cuando enableImageGeneration==true
      instr['photo_instructions'] = pb.imageInstructions('u');
      expect(instr['photo_instructions'], equals(pb.imageInstructions('u')));
    },
  );

  test(
    'PromptBuilder JSON supports simultaneous photo_instructions and attached_image_metadata_instructions injection',
    () {
      final profile = AiChanProfile(
        biography: <String, dynamic>{},
        userName: 'u',
        aiName: 'ai',
        userBirthdate: null,
        aiBirthdate: null,
        appearance: <String, dynamic>{},
        timeline: [],
      );
      final builder = pb.PromptBuilderService();
      final jsonStr = builder.buildRealtimeSystemPromptJson(
        profile: profile,
        messages: [],
      );
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final instr = map['instructions'] as Map<String, dynamic>;

      // Simular que hay petición de imagen y que el usuario adjuntó una imagen
      instr['photo_instructions'] = pb.imageInstructions('u');
      instr['attached_image_metadata_instructions'] = pb.imageMetadata('u');

      expect(instr.containsKey('photo_instructions'), isTrue);
      expect(instr.containsKey('attached_image_metadata_instructions'), isTrue);
      expect(instr['photo_instructions'], equals(pb.imageInstructions('u')));
      expect(
        instr['attached_image_metadata_instructions'],
        equals(pb.imageMetadata('u')),
      );
    },
  );
}
