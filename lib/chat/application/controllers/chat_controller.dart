import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';
import 'package:ai_chan/chat/application/controllers/_chat_audio_controller.dart';
import 'package:ai_chan/chat/application/controllers/_chat_google_controller.dart';
import 'package:ai_chan/chat/application/controllers/_chat_call_controller.dart';
import 'package:ai_chan/chat/application/controllers/_chat_message_controller.dart';
import 'package:ai_chan/chat/application/controllers/_chat_data_controller.dart';

// Barrel exports for sub-controllers - Clean single import access
export '_chat_audio_controller.dart';
export '_chat_google_controller.dart';
export '_chat_call_controller.dart';
export '_chat_message_controller.dart';
export '_chat_data_controller.dart';

/// DDD Chat Controller - Core chat operations with specialized sub-controllers
class ChatController extends ChangeNotifier with UIStateManagementMixin {
  ChatController({required final ChatApplicationService chatService})
    : _chatService = chatService,
      audioController = ChatAudioController(chatService: chatService),
      googleController = ChatGoogleController(chatService: chatService),
      callController = ChatCallController(chatService: chatService),
      messageController = ChatMessageController(chatService: chatService),
      dataController = ChatDataController(chatService: chatService);

  final ChatApplicationService _chatService;
  final ChatAudioController audioController;
  final ChatGoogleController googleController;
  final ChatCallController callController;
  final ChatMessageController messageController;
  final ChatDataController dataController;

  // Core getters - State access
  List<Message> get messages => _chatService.messages;
  AiChanProfile? get profile => dataController.profile;
  List<EventEntry> get events => dataController.events;
  List<TimelineEntry> get timeline => dataController.timeline;
  String? get selectedModel => dataController.selectedModel;

  bool get isTyping => messageController.isTyping;
  bool get isSendingImage => messageController.isSendingImage;
  bool get googleLinked => googleController.googleLinked;
  bool get isCalling => callController.isCalling;
  bool get isRecording => audioController.isRecording;

  List<int> get currentWaveform => audioController.currentWaveform;
  String get liveTranscript => audioController.liveTranscript;
  Duration get recordingElapsed => audioController.recordingElapsed;
  Duration get playingPosition => audioController.playingPosition;
  Duration get playingDuration => audioController.playingDuration;

  bool get isSendingAudio => audioController.isSendingAudio;
  bool get isUploadingUserAudio => audioController.isUploadingUserAudio;

  IAudioChatService get audioService => audioController.audioService;
  bool get hasPendingIncomingCall => callController.hasPendingIncomingCall;
  int get queuedCount => callController.queuedCount;

  String? get googleEmail => googleController.googleEmail;
  String? get googleAvatarUrl => googleController.googleAvatarUrl;
  String? get googleName => googleController.googleName;

  Future<void> initialize() async => await executeWithState(
    operation: () => _chatService.initialize(),
    errorMessage: 'Error al cargar chat',
  );
  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
  }) async {
    if (_chatService.profile == null) {
      executeSyncWithNotification(
        operation: () => throw Exception('Perfil no inicializado'),
        errorMessage: 'Perfil no inicializado',
      );
      return;
    }
    await executeWithState(
      operation: () =>
          _chatService.sendMessage(text: text, model: model, image: image),
      errorMessage: 'Error al enviar mensaje',
    );
  }

  Future<void> clearMessages() async => await executeWithState(
    operation: () => _chatService.clearAll(),
    errorMessage: 'Error al limpiar mensajes',
  );
  Future<void> saveState() async {
    await executeWithNotification(
      operation: () async {
        final data = _chatService.exportToData();
        await _chatService.saveAll(data);
      },
      errorMessage: 'Error al guardar',
    );
  }

  // Service-level operations that don't require coordination
  void setSelectedModel(final String? model) => executeSyncWithNotification(
    operation: () => _chatService.setSelectedModel(model),
  );

  Future<List<String>> getAllModels({final bool forceRefresh = false}) async =>
      await _chatService.getAllModels(forceRefresh: forceRefresh);

  void schedulePromiseEvent(final EventEntry event) =>
      executeSyncWithNotification(
        operation: () => _chatService.schedulePromiseEvent(event),
      );

  bool isPlaying(final Message msg) => _chatService.isPlaying(msg);

  // Core coordination operations
  Future<String> exportChat() async {
    final data = _chatService.exportToData();
    return await dataController.exportAllToJson(data);
  }

  Future<void> applyChatExport(final Map<String, dynamic> chatExport) async =>
      await executeWithState(
        operation: () => _chatService.applyChatExport(chatExport),
        errorMessage: 'Error al importar chat',
      );

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }
}
