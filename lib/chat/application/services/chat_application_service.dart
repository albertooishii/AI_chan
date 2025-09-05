import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/chat/domain/interfaces/i_prompt_builder_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/core/di.dart' as di;

/// Application Service que maneja la lógica de negocio del chat.
/// Orquesta casos de uso y servicios de dominio.
/// Esta clase reemplaza gradualmente las responsabilidades de ChatProvider.
class ChatApplicationService {
  final IChatRepository _repository;
  final IPromptBuilderService _promptBuilder;
  late final IAudioChatService _audioService;

  // Estado interno del servicio
  List<Message> _messages = [];
  AiChanProfile? _profile;
  List<EventEntry> _events = [];
  String? _selectedModel;
  bool _googleLinked = false;

  ChatApplicationService({
    required IChatRepository repository,
    required IPromptBuilderService promptBuilder,
  })  : _repository = repository,
        _promptBuilder = promptBuilder {
    // Inicializar audio service con callbacks vacíos por ahora
    _audioService = di.getAudioChatService(
      onStateChanged: () {},
      onWaveform: (waveform) {},
    );
  }

  // Getters públicos
  List<Message> get messages => List.unmodifiable(_messages);
  AiChanProfile? get profile => _profile;
  List<EventEntry> get events => List.unmodifiable(_events);
  String? get selectedModel => _selectedModel;
  bool get googleLinked => _googleLinked;

  // Audio relacionado
  IAudioChatService get audioService => _audioService;
  bool get isRecording => _audioService.isRecording;
  List<int> get currentWaveform => _audioService.currentWaveform;
  String get liveTranscript => _audioService.liveTranscript;
  Duration get recordingElapsed => _audioService.recordingElapsed;
  Duration get playingPosition => _audioService.currentPosition;
  Duration get playingDuration => _audioService.currentDuration;

  /// Inicializa el servicio cargando datos
  Future<void> initialize() async {
    final data = await _repository.loadAll();
    if (data != null) {
      _loadFromData(data);
    }
  }

  /// Envía un mensaje
  Future<void> sendMessage({
    required String text,
    String? model,
    dynamic image,
  }) async {
    if (_profile == null) throw Exception('Perfil no inicializado');

    final message = Message(
      text: text,
      sender: MessageSender.user,
      dateTime: DateTime.now(),
      isImage: image != null,
      image: image,
    );

    _messages.add(message);
    await _persistState();

    // Procesar respuesta de IA (implementación básica)
    await _processSendMessage(message, model);
  }

  /// Procesa el envío de un mensaje
  Future<void> _processSendMessage(Message message, String? model) async {
    try {
      // Simular procesamiento de IA
      await Future.delayed(const Duration(seconds: 1));
      
      final responseMessage = Message(
        text: 'Respuesta de IA para: ${message.text}',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
      );
      
      _messages.add(responseMessage);
      await _persistState();
    } catch (e) {
      rethrow;
    }
  }

  /// Audio methods
  Future<void> startRecording() => _audioService.startRecording();
  Future<void> cancelRecording() => _audioService.cancelRecording();
  
  Future<String?> stopAndSendRecording({String? model}) async {
    return await _audioService.stopRecording();
  }

  Future<void> togglePlayAudio(Message msg) async {
    await _audioService.togglePlay(msg, () {});
  }

  Future<void> generateTtsForMessage(Message msg, {String voice = 'nova'}) async {
    final path = await _audioService.synthesizeTts(msg.text, voice: voice);
    if (path != null) {
      // Asociar audio con mensaje
    }
  }

  /// Event management
  void schedulePromiseEvent(EventEntry event) {
    _events.add(event);
  }

  /// Model management
  void setSelectedModel(String? model) {
    _selectedModel = model;
  }

  Future<List<String>> getAllModels({bool forceRefresh = false}) async {
    return ['gpt-4', 'gpt-3.5-turbo', 'claude-3'];
  }

  /// Google integration
  void setGoogleLinked(bool linked) {
    _googleLinked = linked;
  }

  Future<Map<String, dynamic>> diagnoseGoogleState() async {
    return {
      'googleLinked': _googleLinked,
      'chatProviderState': {
        'googleEmail': 'test@example.com',
        'googleName': 'Test User',
      },
    };
  }

  /// Profile management
  void updateProfile(AiChanProfile profile) {
    _profile = profile;
  }

  /// Prompt building
  String buildRealtimeSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    int maxRecent = 32,
  }) => _promptBuilder.buildRealtimeSystemPromptJson(
    profile: profile, 
    messages: messages, 
    maxRecent: maxRecent
  );

  String buildCallSystemPromptJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required bool aiInitiatedCall,
    int maxRecent = 32,
  }) => _promptBuilder.buildCallSystemPromptJson(
    profile: profile,
    messages: messages,
    aiInitiatedCall: aiInitiatedCall,
    maxRecent: maxRecent,
  );

  /// Persistence methods
  Future<void> saveAll(Map<String, dynamic> exportedJson) async {
    await _repository.saveAll(exportedJson);
  }

  Future<Map<String, dynamic>?> loadAll() async {
    return await _repository.loadAll();
  }

  Future<void> clearAll() async {
    await _repository.clearAll();
    _messages.clear();
    _events.clear();
    _profile = null;
  }

  Future<String> exportAllToJson(Map<String, dynamic> exportedJson) async {
    return await _repository.exportAllToJson(exportedJson);
  }

  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr) async {
    return await _repository.importAllFromJson(jsonStr);
  }

  Future<void> applyImportedChat(Map<String, dynamic> imported) async {
    _loadFromData(imported);
    await _persistState();
  }

  /// Estado interno
  Future<void> _persistState() async {
    final data = exportToData();
    await _repository.saveAll(data);
  }

  void _loadFromData(Map<String, dynamic> data) {
    if (data['profile'] != null) {
      _profile = AiChanProfile.fromJson(data['profile']);
    }
    if (data['messages'] != null) {
      _messages = (data['messages'] as List).map((m) => Message.fromJson(m)).toList();
    }
    if (data['events'] != null) {
      _events = (data['events'] as List).map((e) => EventEntry.fromJson(e)).toList();
    }
    if (data['selectedModel'] != null) {
      _selectedModel = data['selectedModel'];
    }
    if (data['googleLinked'] != null) {
      _googleLinked = data['googleLinked'];
    }
  }

  Map<String, dynamic> exportToData() {
    return {
      'profile': _profile?.toJson(),
      'messages': _messages.map((m) => m.toJson()).toList(),
      'events': _events.map((e) => e.toJson()).toList(),
      'selectedModel': _selectedModel,
      'googleLinked': _googleLinked,
    };
  }

  /// Limpieza de recursos
  void dispose() {
    _audioService.dispose();
  }
}
