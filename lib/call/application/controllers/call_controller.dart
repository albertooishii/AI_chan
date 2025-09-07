import 'package:flutter/foundation.dart';
import '../../domain/entities/voice_call_state.dart';
import '../../../chat/domain/models/message.dart';

/// CallController - Main coordinator for call operations
class CallController extends ChangeNotifier {
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
    try {
      _currentPhase = CallPhase.initializing;
      _resetCallState();
      debugPrint('📞 [CALL] Call system initialized');
    } on Exception catch (e) {
      debugPrint('Error in initialize: $e');
      rethrow;
    }
  }

  /// Start outgoing call
  Future<void> startCall() async {
    try {
      _currentPhase = CallPhase.connecting;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      _currentPhase = CallPhase.active;
      _isCallActive = true;
      _isUserTurn = true;
      notifyListeners();
      debugPrint('📞 [CALL] Call started');
    } on Exception catch (e) {
      debugPrint('Error in startCall: $e');
      rethrow;
    }
  }

  /// Accept incoming call
  Future<void> acceptCall() async {
    try {
      _currentPhase = CallPhase.active;
      _isCallActive = true;
      _isUserTurn = true;
      notifyListeners();
      debugPrint('📞 [CALL] Call accepted');
    } on Exception catch (e) {
      debugPrint('Error in acceptCall: $e');
      rethrow;
    }
  }

  /// Hang up call
  Future<void> hangUp() async {
    try {
      _currentPhase = CallPhase.ending;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 300));
      _currentPhase = CallPhase.ended;
      _isCallActive = false;
      _resetCallState();
      notifyListeners();
      debugPrint('📞 [CALL] Call ended');
    } on Exception catch (e) {
      debugPrint('Error in hangUp: $e');
      rethrow;
    }
  }

  /// Toggle microphone mute
  Future<void> toggleMute() async {
    try {
      _isMuted = !_isMuted;
      notifyListeners();
      debugPrint('📞 [CALL] Mute toggled: $_isMuted');
    } on Exception catch (e) {
      debugPrint('Error in toggleMute: $e');
      rethrow;
    }
  }

  /// Send text message during call
  Future<void> sendMessage(final String text) async {
    try {
      final message = VoiceCallMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      );
      _messageHistory.add(message);
      _isUserTurn = false;
      notifyListeners();
      debugPrint('📞 [CALL] Message sent: $text');
    } on Exception catch (e) {
      debugPrint('Error in sendMessage: $e');
      rethrow;
    }
  }

  /// Handle incoming AI message
  void handleIncomingMessage(final String text) {
    try {
      final message = VoiceCallMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
      );
      _messageHistory.add(message);
      _isAiSpeaking = true;
      _isUserTurn = true;
      if (_messageHistory.length > 100) _messageHistory.removeAt(0);
      notifyListeners();
      debugPrint('📞 [CALL] Incoming message: $text');
    } on Exception catch (e) {
      debugPrint('Error in handleIncomingMessage: $e');
    }
  }

  /// Process incoming audio data
  Future<void> processAudioData(final Uint8List audioData) async {
    try {
      _isAiSpeaking = true;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint('📞 [CALL] Audio data processed');
    } on Exception catch (e) {
      debugPrint('Error in processAudioData: $e');
      rethrow;
    }
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
