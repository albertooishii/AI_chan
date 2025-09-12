import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_controller.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/presentation/controllers/_chat_audio_controller.dart';
import 'package:ai_chan/chat/presentation/controllers/_chat_google_controller.dart';
import 'package:ai_chan/chat/presentation/controllers/_chat_call_controller.dart';
import 'package:ai_chan/chat/presentation/controllers/_chat_message_controller.dart';
import 'package:ai_chan/chat/presentation/controllers/_chat_data_controller.dart';

// Barrel exports for sub-controllers - Clean single import access
export '_chat_audio_controller.dart';
export '_chat_google_controller.dart';
export '_chat_call_controller.dart';
export '_chat_message_controller.dart';
export '_chat_data_controller.dart';

/// DDD Chat Controller - Core chat operations with specialized sub-controllers
/// Implements IChatController interface for Clean Architecture compliance
class ChatController extends ChangeNotifier implements IChatController {
  ChatController({required final ChatApplicationService chatService})
    : _chatService = chatService,
      audioController = ChatAudioController(chatService: chatService),
      googleController = ChatGoogleController(chatService: chatService),
      callController = ChatCallController(chatService: chatService),
      messageController = ChatMessageController(chatService: chatService),
      dataController = ChatDataController(chatService: chatService) {
    // Conectar listeners de sub-controladores para propagar notificaciones
    _setupSubControllerListeners();
  }

  final ChatApplicationService _chatService;
  @override
  final ChatAudioController audioController;
  @override
  final ChatGoogleController googleController;
  @override
  final ChatCallController callController;
  @override
  final ChatMessageController messageController;
  @override
  final ChatDataController dataController;

  void _setupSubControllerListeners() {
    // Escuchar cambios en el dataController
    dataController.addListener(_onSubControllerChanged);
    // Escuchar cambios en el messageController
    messageController.addListener(_onSubControllerChanged);
    // Escuchar cambios en el audioController
    audioController.addListener(_onSubControllerChanged);
    // Escuchar cambios en el googleController
    googleController.addListener(_onSubControllerChanged);
    // Escuchar cambios en el callController
    callController.addListener(_onSubControllerChanged);
  }

  void _onSubControllerChanged() {
    // Propagar notificaciones de sub-controladores al ChatController
    notifyListeners();
  }

  // Core getters - State access
  @override
  List<Message> get messages => _chatService.messages;
  @override
  AiChanProfile? get profile => dataController.profile;
  List<ChatEvent> get events => dataController.events;
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

  @override
  Future<void> initialize() async {
    try {
      await _chatService.initialize();
      // Configurar callback para notificaciones de estado después de la inicialización
      _chatService.setOnStateChanged(() {
        debugPrint(
          'ChatController: Received state change notification from service',
        );
        notifyListeners();
      });
    } on Exception catch (e) {
      debugPrint('Error in initialize: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
  }) async {
    if (_chatService.profile == null) {
      throw Exception('Perfil no inicializado');
    }
    try {
      debugPrint('ChatController: sendMessage called with text: $text');
      await _chatService.sendMessage(
        text: text,
        image: image,
      ); // Model selection is now automatic
      debugPrint(
        'ChatController: sendMessage completed, messages count: ${_chatService.messages.length}',
      );
      notifyListeners(); // Notificar a la UI que el estado ha cambiado
      debugPrint('ChatController: notifyListeners called');
    } on Exception catch (e) {
      debugPrint('Error in sendMessage: $e');
      rethrow;
    }
  }

  @override
  Future<void> clearMessages() async {
    try {
      await _chatService.clearAll();
      notifyListeners(); // Notificar a la UI que el estado ha cambiado
    } on Exception catch (e) {
      debugPrint('Error in clearMessages: $e');
      rethrow;
    }
  }

  @override
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
      notifyListeners(); // Notificar a la UI que el estado ha cambiado
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

  void schedulePromiseEvent(final ChatEvent event) {
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
      notifyListeners(); // Notificar a la UI que el estado ha cambiado
    } on Exception catch (e) {
      debugPrint('Error in applyChatExport: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    // Limpiar listeners de sub-controladores
    dataController.removeListener(_onSubControllerChanged);
    messageController.removeListener(_onSubControllerChanged);
    audioController.removeListener(_onSubControllerChanged);
    googleController.removeListener(_onSubControllerChanged);
    callController.removeListener(_onSubControllerChanged);

    _chatService.dispose();
    super.dispose();
  }
}
