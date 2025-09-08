import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/use_cases/send_message_use_case.dart';
import 'package:ai_chan/chat/application/services/message_retry_service.dart';
import 'package:ai_chan/chat/application/services/message_image_processing_service.dart';
import 'package:ai_chan/chat/infrastructure/ai/chat_ai_service_adapter.dart';
import 'package:ai_chan/chat/infrastructure/logging/chat_logger_adapter.dart';
import 'package:ai_chan/chat/infrastructure/image/chat_image_service_adapter.dart';
import 'package:ai_chan/chat/infrastructure/events/chat_event_timeline_service_adapter.dart';
import '../fakes/fake_ai_service.dart';
import '../test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });
  test(
    'SendMessageUseCase uses AIService when no injectedService provided',
    () async {
      final fake = FakeAIService.withText('hola desde fake');
      // For test that asserts method called, wrap to detect usage
      AIService.testOverride = fake;

      // Use proper dependency injection instead of relying on stub implementations
      final logger = ChatLoggerAdapter();
      final aiServiceAdapter = const ChatAIServiceAdapter();
      final retryService = MessageRetryService(aiServiceAdapter);
      final imageService = MessageImageProcessingService(
        const ChatImageServiceAdapter(),
        logger,
      );
      final useCase = SendMessageUseCase(
        retryService: retryService,
        imageService: imageService,
        eventTimelineService: const ChatEventTimelineServiceAdapter(),
      );

      final recent = <Message>[
        Message(
          text: 'hola',
          sender: MessageSender.user,
          dateTime: DateTime.now(),
          status: MessageStatus.sent,
        ),
      ];
      final profile = AiChanProfile(
        userName: 'u',
        aiName: 'ai',
        userBirthdate: DateTime(2000),
        aiBirthdate: DateTime(2000),
        biography: {},
        appearance: {},
      );
      final systemPrompt = SystemPrompt(
        profile: profile,
        dateTime: DateTime.now(),
        recentMessages: [],
        instructions: {},
      );

      final outcome = await useCase.sendChat(
        recentMessages: recent,
        systemPromptObj: systemPrompt,
        model: 'gpt-fake',
      );

      expect(fake.called, isTrue);
      expect(outcome.result.text, contains('hola desde fake'));

      AIService.testOverride = null;
    },
  );

  test('SendMessageUseCase extracts inner audio text and requests TTS', () async {
    final fake = FakeAIService.withAudio('[audio] ¡Hola audio! [/audio]');
    AIService.testOverride = fake;

    // Use proper dependency injection instead of relying on stub implementations
    final logger = ChatLoggerAdapter();
    final aiServiceAdapter = const ChatAIServiceAdapter();
    final retryService = MessageRetryService(aiServiceAdapter);
    final imageService = MessageImageProcessingService(
      const ChatImageServiceAdapter(),
      logger,
    );
    final useCase = SendMessageUseCase(
      retryService: retryService,
      imageService: imageService,
      eventTimelineService: const ChatEventTimelineServiceAdapter(),
    );

    final recent = <Message>[
      Message(
        text: 'hola',
        sender: MessageSender.user,
        dateTime: DateTime.now(),
        status: MessageStatus.sent,
      ),
    ];
    final profile = AiChanProfile(
      userName: 'u',
      aiName: 'ai',
      userBirthdate: DateTime(2000),
      aiBirthdate: DateTime(2000),
      biography: {},
      appearance: {},
    );
    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      recentMessages: [],
      instructions: {},
    );

    final outcome2 = await useCase.sendChat(
      recentMessages: recent,
      systemPromptObj: systemPrompt,
      model: 'gpt-fake',
    );

    expect(outcome2.ttsRequested, isTrue);
    expect(outcome2.result.text, equals('¡Hola audio!'));
    expect(outcome2.assistantMessage.text, equals('¡Hola audio!'));

    AIService.testOverride = null;
  });

  test(
    'SendMessageUseCase leaves text unchanged and ttsRequested false when no audio tag',
    () async {
      final fake2 = FakeAIService.withText('Texto normal sin tag');
      AIService.testOverride = fake2;

      // Use proper dependency injection instead of relying on stub implementations
      final logger = ChatLoggerAdapter();
      final aiServiceAdapter = const ChatAIServiceAdapter();
      final retryService = MessageRetryService(aiServiceAdapter);
      final imageService = MessageImageProcessingService(
        const ChatImageServiceAdapter(),
        logger,
      );
      final useCase2 = SendMessageUseCase(
        retryService: retryService,
        imageService: imageService,
        eventTimelineService: const ChatEventTimelineServiceAdapter(),
      );

      final recent2 = <Message>[
        Message(
          text: 'hola',
          sender: MessageSender.user,
          dateTime: DateTime.now(),
          status: MessageStatus.sent,
        ),
      ];
      final profile2 = AiChanProfile(
        userName: 'u',
        aiName: 'ai',
        userBirthdate: DateTime(2000),
        aiBirthdate: DateTime(2000),
        biography: {},
        appearance: {},
      );
      final systemPrompt2 = SystemPrompt(
        profile: profile2,
        dateTime: DateTime.now(),
        recentMessages: [],
        instructions: {},
      );

      final outcome3 = await useCase2.sendChat(
        recentMessages: recent2,
        systemPromptObj: systemPrompt2,
        model: 'gpt-fake',
      );

      expect(outcome3.ttsRequested, isFalse);
      expect(outcome3.result.text, equals('Texto normal sin tag'));
      expect(outcome3.assistantMessage.text, equals('Texto normal sin tag'));

      AIService.testOverride = null;
    },
  );
}
