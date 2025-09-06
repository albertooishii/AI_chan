import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro

/// Application Controller for Chat Screen
/// Orchestrates business logic for the chat interface
/// Following Clean Architecture principles
class ChatScreenController extends ChangeNotifier {
  ChatScreenController({
    required final ChatController chatController,
  }) // ✅ DDD: ETAPA 3 - DDD puro
  : _chatController = chatController;
  final ChatController _chatController; // ✅ DDD: ETAPA 3 - DDD puro

  // UI State
  bool _isLoading = false;
  String? _errorMessage;
  int _displayedMessageCount = 50;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get displayedMessageCount => _displayedMessageCount;
  ChatController get chatController =>
      _chatController; // ✅ DDD: ETAPA 3 - DDD puro

  // UI State Management
  void setLoading(final bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void setError(final String? error) {
    if (_errorMessage != error) {
      _errorMessage = error;
      notifyListeners();
    }
  }

  void clearError() => setError(null);

  // Message Display Logic
  void loadMoreMessages() {
    _displayedMessageCount += 50;
    notifyListeners();
  }

  List<Message> getFilteredMessages() {
    return _chatController
        .messages // ✅ DDD: ETAPA 3 - usar ChatController directo
        .where(
          (final m) =>
              m.sender != MessageSender.system ||
              (m.sender == MessageSender.system && m.text.contains('[call]')),
        )
        .toList();
  }

  List<Message> getDisplayedMessages() {
    final filtered = getFilteredMessages();
    if (filtered.isEmpty) return [];

    final take = filtered.length <= _displayedMessageCount
        ? filtered.length
        : _displayedMessageCount;
    return filtered.sublist(filtered.length - take, filtered.length);
  }

  // Chat Operations - delegate to ChatProvider
  Future<void> sendMessage(final String message) async {
    try {
      setLoading(true);
      clearError();

      await _chatController.sendMessage(
        text: message,
      ); // ✅ DDD: ETAPA 3 - usar ChatController directo
    } catch (e) {
      setError('Error sending message: $e');
    } finally {
      setLoading(false);
    }
  }

  // Model Selection
  void selectModel(final String model) {
    try {
      clearError();
      _chatController.setSelectedModel(
        model,
      ); // ✅ DDD: ETAPA 3 - usar ChatController directo
    } catch (e) {
      setError('Error changing model: $e');
    }
  }

  // Voice Call Integration
  bool shouldShowVoiceCallScreen() {
    return false; // TODO: Implement proper voice call detection
  }

  // Additional helper methods
  String get currentModel =>
      _chatController.selectedModel ?? 'No model selected'; // ✅ DDD: ETAPA 3
  bool get hasMessages => _chatController.messages.isNotEmpty; // ✅ DDD: ETAPA 3
  bool get isSending => _isLoading; // Use local loading state
}
