import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';

/// Controller para la UI del chat.
/// Maneja estado de presentación y eventos de usuario.
/// NO contiene lógica de negocio.
class ChatController extends ChangeNotifier {
  final ChatApplicationService _chatService;

  // Estado UI
  List<Message> _messages = [];
  AiChanProfile? _profile;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters para UI
  List<Message> get messages => List.unmodifiable(_messages);
  AiChanProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  ChatController({required ChatApplicationService chatService}) : _chatService = chatService;

  /// Inicializa el chat cargando datos
  Future<void> initialize() async {
    _setLoading(true);
    try {
      final data = await _chatService.loadAll();
      if (data != null) {
        _loadFromData(data);
      }
      _clearError();
    } catch (e) {
      _setError('Error al cargar chat: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Envía un mensaje
  Future<void> sendMessage({required String text, String? model, dynamic image}) async {
    if (_profile == null) {
      _setError('Perfil no inicializado');
      return;
    }

    _setLoading(true);
    try {
      // Aquí llamaríamos al caso de uso de envío
      // Por ahora solo agregamos el mensaje localmente
      final message = Message(
        text: text,
        sender: MessageSender.user,
        dateTime: DateTime.now(),
        isImage: image != null,
        image: image,
      );

      _addMessage(message);
      _clearError();
    } catch (e) {
      _setError('Error al enviar mensaje: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Limpia todos los mensajes
  Future<void> clearMessages() async {
    _setLoading(true);
    try {
      await _chatService.clearAll();
      _messages.clear();
      _clearError();
      notifyListeners();
    } catch (e) {
      _setError('Error al limpiar mensajes: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Guarda el estado actual
  Future<void> saveState() async {
    if (_profile == null) return;

    try {
      final data = _exportToData();
      await _chatService.saveAll(data);
      _clearError();
    } catch (e) {
      _setError('Error al guardar: $e');
    }
  }

  // Métodos privados para manejo de estado
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  void _loadFromData(Map<String, dynamic> data) {
    // Lógica para cargar desde datos guardados
    // Por ahora implementación básica
    if (data['profile'] != null) {
      _profile = AiChanProfile.fromJson(data['profile']);
    }
    if (data['messages'] != null) {
      _messages = (data['messages'] as List).map((m) => Message.fromJson(m)).toList();
    }
    notifyListeners();
  }

  Map<String, dynamic> _exportToData() {
    return {'profile': _profile?.toJson(), 'messages': _messages.map((m) => m.toJson()).toList()};
  }

  /// Actualiza el perfil
  void updateProfile(AiChanProfile profile) {
    _profile = profile;
    notifyListeners();
  }
}
