import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';

/// Application Controller for Chat Screen
/// Orchestrates business logic for the chat interface
/// Following Clean Architecture principles
class ChatScreenController extends ChangeNotifier {
  final ChatProvider _chatProvider;

  // UI State
  bool _isLoading = false;
  String? _errorMessage;
  int _displayedMessageCount = 50;

  ChatScreenController({required ChatProvider chatProvider})
    : _chatProvider = chatProvider;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get displayedMessageCount => _displayedMessageCount;
  ChatProvider get chatProvider => _chatProvider;

  // UI State Management
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void setError(String? error) {
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
    return _chatProvider.messages
        .where(
          (m) =>
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
  Future<void> sendMessage(String message) async {
    try {
      setLoading(true);
      clearError();

      await _chatProvider.sendMessage(message);
    } catch (e) {
      setError('Error sending message: $e');
    } finally {
      setLoading(false);
    }
  }

  // Model Selection
  void selectModel(String model) {
    try {
      clearError();
      _chatProvider.selectedModel = model;
    } catch (e) {
      setError('Error changing model: $e');
    }
  }

  // Voice Call Integration
  bool shouldShowVoiceCallScreen() {
    return false; // TODO: Implement proper voice call detection
  }

  // Additional helper methods
  String get currentModel => _chatProvider.selectedModel ?? 'No model selected';
  bool get hasMessages => _chatProvider.messages.isNotEmpty;
  bool get isSending => _isLoading; // Use local loading state
}
