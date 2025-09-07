import 'package:flutter/foundation.dart';
import '../../../chat/application/mixins/ui_state_management_mixin.dart';
import '../../domain/entities/voice_call_state.dart';
import '../../../chat/domain/models/message.dart';

/// CallController - Main coordinator for call operations
class CallController extends ChangeNotifier with UIStateManagementMixin {
  CallController();

  // Core state
  CallPhase _currentPhase = CallPhase.initializing;
  bool _isCallActive = false;
  Duration _callDuration = Duration.zero;
  bool _isMuted = false;
  bool _isAiSpeaking = false;
  bool _isUserTurn = true;
  String _connectionQuality = 'good';
  final List<VoiceCallMessage> _messageHistory = [];

  // Getters
  CallPhase get currentPhase => _currentPhase;
  bool get isCallActive => _isCallActive;
  bool get isMuted => _isMuted;
  bool get isAiSpeaking => _isAiSpeaking;
  bool get isUserTurn => _isUserTurn;
  Duration get callDuration => _callDuration;
  String get connectionQuality => _connectionQuality;
  List<VoiceCallMessage> get messageHistory =>
      List.unmodifiable(_messageHistory);

  /// Initialize call system
  Future<void> initialize() async {
    await executeWithState(
      operation: () async {
        _currentPhase = CallPhase.initializing;
        _resetCallState();
      },
      errorMessage: 'Failed to initialize call system',
    );
  }

  /// Start outgoing call
  Future<void> startCall() async {
    await executeWithState(
      operation: () async {
        _currentPhase = CallPhase.connecting;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 500));
        _currentPhase = CallPhase.active;
        _isCallActive = true;
        _isUserTurn = true;
        notifyListeners();
      },
      errorMessage: 'Failed to start call',
    );
  }

  /// Accept incoming call
  Future<void> acceptCall() async {
    await executeWithState(
      operation: () async {
        _currentPhase = CallPhase.active;
        _isCallActive = true;
        _isUserTurn = true;
        notifyListeners();
      },
      errorMessage: 'Failed to accept call',
    );
  }

  /// Hang up call
  Future<void> hangUp() async {
    await executeWithState(
      operation: () async {
        _currentPhase = CallPhase.ending;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 300));
        _currentPhase = CallPhase.ended;
        _isCallActive = false;
        _resetCallState();
        notifyListeners();
      },
      errorMessage: 'Failed to hang up call',
    );
  }

  /// Toggle microphone mute
  Future<void> toggleMute() async {
    await executeWithState(
      operation: () async {
        _isMuted = !_isMuted;
        notifyListeners();
      },
      errorMessage: 'Failed to toggle mute',
    );
  }

  /// Send text message during call
  Future<void> sendMessage(final String text) async {
    await executeWithState(
      operation: () async {
        final message = VoiceCallMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        );
        _messageHistory.add(message);
        _isUserTurn = false;
        notifyListeners();
      },
      errorMessage: 'Failed to send message',
    );
  }

  /// Handle incoming AI message
  void handleIncomingMessage(final String text) {
    executeSyncWithNotification(
      operation: () {
        final message = VoiceCallMessage(
          text: text,
          isUser: false,
          timestamp: DateTime.now(),
        );
        _messageHistory.add(message);
        _isAiSpeaking = true;
        _isUserTurn = true;
        if (_messageHistory.length > 100) _messageHistory.removeAt(0);
      },
      errorMessage: 'Failed to handle incoming message',
    );
  }

  /// Process incoming audio data
  Future<void> processAudioData(final Uint8List audioData) async {
    await executeWithState(
      operation: () async {
        _isAiSpeaking = true;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 100));
      },
      errorMessage: 'Failed to process audio data',
    );
  }

  /// Set AI speaking state
  void setAiSpeaking(final bool speaking) {
    _isAiSpeaking = speaking;
    if (!speaking) _isUserTurn = true;
    notifyListeners();
  }

  /// Update call duration
  void updateCallDuration(final Duration duration) {
    _callDuration = duration;
    notifyListeners();
  }

  /// Update connection quality
  void updateConnectionQuality(final String quality) {
    _connectionQuality = quality;
    notifyListeners();
  }

  /// Get call statistics
  Map<String, dynamic> get callStatistics => {
    'duration': _callDuration,
    'phase': _currentPhase.toString().split('.').last,
    'messageCount': _messageHistory.length,
    'isActive': _isCallActive,
    'connectionQuality': _connectionQuality,
  };

  /// Get recent messages
  List<VoiceCallMessage> getRecentMessages(final int count) {
    if (_messageHistory.length <= count) return List.from(_messageHistory);
    return _messageHistory.sublist(_messageHistory.length - count);
  }

  // Private methods
  void _resetCallState() {
    _callDuration = Duration.zero;
    _isMuted = false;
    _isAiSpeaking = false;
    _isUserTurn = true;
    _connectionQuality = 'good';
    _messageHistory.clear();
  }
}
