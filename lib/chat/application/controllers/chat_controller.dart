import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
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
class ChatController extends ChangeNotifier {
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

  Future<void> initialize() async {
    try {
      await _chatService.initialize();
    } on Exception catch (e) {
      debugPrint('Error in initialize: $e');
      rethrow;
    }
  }

  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
  }) async {
    if (_chatService.profile == null) {
      throw Exception('Perfil no inicializado');
    }
    try {
      await _chatService.sendMessage(text: text, model: model, image: image);
    } on Exception catch (e) {
      debugPrint('Error in sendMessage: $e');
      rethrow;
    }
  }

  Future<void> clearMessages() async {
    try {
      await _chatService.clearAll();
    } on Exception catch (e) {
      debugPrint('Error in clearMessages: $e');
      rethrow;
    }
  }

  Future<void> saveState() async {
    try {
      final data = _chatService.exportToData();
      await _chatService.saveAll(data);
    } on Exception catch (e) {
      debugPrint('Error in saveState: $e');
      rethrow;
    }
  }

  // Service-level operations that don't require coordination
  void setSelectedModel(final String? model) {
    try {
      _chatService.setSelectedModel(model);
    } on Exception catch (e) {
      debugPrint('Error in setSelectedModel: $e');
    }
  }

  Future<List<String>> getAllModels({final bool forceRefresh = false}) async {
    try {
      return await _chatService.getAllModels(forceRefresh: forceRefresh);
    } on Exception catch (e) {
      debugPrint('Error in getAllModels: $e');
      rethrow;
    }
  }

  void schedulePromiseEvent(final EventEntry event) {
    try {
      _chatService.schedulePromiseEvent(event);
    } on Exception catch (e) {
      debugPrint('Error in schedulePromiseEvent: $e');
    }
  }

  bool isPlaying(final Message msg) => _chatService.isPlaying(msg);

  // Core coordination operations
  Future<String> exportChat() async {
    try {
      final data = _chatService.exportToData();
      return await dataController.exportAllToJson(data);
    } on Exception catch (e) {
      debugPrint('Error in exportChat: $e');
      rethrow;
    }
  }

  Future<void> applyChatExport(final Map<String, dynamic> chatExport) async {
    try {
      await _chatService.applyChatExport(chatExport);
    } on Exception catch (e) {
      debugPrint('Error in applyChatExport: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }
}
