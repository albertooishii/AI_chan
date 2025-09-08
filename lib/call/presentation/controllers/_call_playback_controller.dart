import 'package:flutter/material.dart';
import 'dart:async';
import 'package:ai_chan/shared/domain/interfaces/audio_playback_service.dart';
import 'package:ai_chan/call/application/services/call_playback_application_service.dart';

/// Call Playback Controller - Compact audio management with Application Service
class CallPlaybackController extends ChangeNotifier {
  CallPlaybackController({
    required final AudioPlaybackService audioPlayer,
    required final AudioPlaybackService ringPlayer,
  }) : _audioPlayer = audioPlayer,
       _applicationService = CallPlaybackApplicationService(
         audioPlayer: audioPlayer,
         ringPlayer: ringPlayer,
       ) {
    _initializeStreamListeners();
  }

  // Audio services and Application Service
  final AudioPlaybackService _audioPlayer;
  final CallPlaybackApplicationService _applicationService;

  // Core playback state
  bool _isPlayingAIAudio = false, _isPlayingRing = false;
  double _playbackProgress = 0.0, _ringVolume = 0.7, _aiAudioVolume = 0.8;
  String _currentVoice = 'alloy', _playbackStatus = 'stopped';
  String? _currentlyPlayingAudioId;
  Duration _playbackDuration = Duration.zero, _playbackPosition = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription, _durationSubscription;
  StreamSubscription<void>? _completionSubscription;

  // Getters
  bool get isPlayingAIAudio => _isPlayingAIAudio;
  bool get isPlayingRing => _isPlayingRing;
  double get playbackProgress => _playbackProgress;
  double get ringVolume => _ringVolume;
  double get aiAudioVolume => _aiAudioVolume;
  String get currentVoice => _currentVoice;
  String get playbackStatus => _playbackStatus;
  String? get currentlyPlayingAudioId => _currentlyPlayingAudioId;
  Duration get playbackDuration => _playbackDuration;
  Duration get playbackPosition => _playbackPosition;
  bool get isAnyAudioPlaying => _isPlayingAIAudio || _isPlayingRing;

  /// Play/Stop AI audio using Application Service
  Future<void> playAIAudio(
    final String audioPath, {
    final String? audioId,
  }) async {
    try {
      final result = await _applicationService.playAIAudio(
        audioPath,
        audioId: audioId,
      );
      if (result.success) {
        _currentlyPlayingAudioId = result.audioId;
        _updateAudioState(true, result.status ?? 'playing');
        notifyListeners();
        debugPrint('🎵 [AUDIO] Playing AI audio: $audioId');
      } else {
        throw Exception(result.error);
      }
    } on Exception catch (e) {
      debugPrint('Error in playAIAudio: $e');
      rethrow;
    }
  }

  /// Stop AI audio using Application Service
  Future<void> stopAIAudio() async {
    try {
      final result = await _applicationService.stopAIAudio();
      if (result.success) {
        _updateAudioState(false, result.status ?? 'stopped');
        notifyListeners();
        debugPrint('⏹️ [AUDIO] AI audio stopped');
      } else {
        throw Exception(result.error);
      }
    } on Exception catch (e) {
      debugPrint('Error in stopAIAudio: $e');
      rethrow;
    }
  }

  /// Start ring using Application Service
  Future<void> startRing() async {
    if (_isPlayingRing) return;

    try {
      final result = await _applicationService.manageRingTone(shouldRing: true);
      if (result.success) {
        _isPlayingRing = true;
        notifyListeners();
        debugPrint('🔔 [RING] Ring started');
      } else {
        throw Exception(result.error);
      }
    } on Exception catch (e) {
      debugPrint('Error in startRing: $e');
      rethrow;
    }
  }

  /// Stop ring using Application Service
  Future<void> stopRing() async {
    if (!_isPlayingRing) return;

    try {
      final result = await _applicationService.manageRingTone(
        shouldRing: false,
      );
      if (result.success) {
        _isPlayingRing = false;
        notifyListeners();
        debugPrint('🔕 [RING] Ring stopped');
      } else {
        throw Exception(result.error);
      }
    } on Exception catch (e) {
      debugPrint('Error in stopRing: $e');
      rethrow;
    }
  }

  /// Set volume levels (UI only)
  void setPlaybackVolume(final double volume) {
    try {
      _aiAudioVolume = volume.clamp(0.0, 1.0);
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Error in setPlaybackVolume: $e');
    }
  }

  void setRingVolume(final double volume) {
    try {
      _ringVolume = volume.clamp(0.0, 1.0);
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Error in setRingVolume: $e');
    }
  }

  /// Update voice selection using Application Service
  void updateVoice(final String voice) {
    try {
      _currentVoice = _applicationService.resolveVoiceConfiguration(voice);
      notifyListeners();
      debugPrint('🎤 [VOICE] Selected: $_currentVoice');
    } on Exception catch (e) {
      debugPrint('Error in updateVoice: $e');
    }
  }

  /// Check if microphone should be unmuted using Application Service
  bool shouldUnmuteMic() {
    try {
      final recommendation = _applicationService.calculateUnmuteTiming(
        position: _playbackPosition,
        duration: _playbackDuration,
        isPlaying: _isPlayingAIAudio,
      );
      return recommendation.shouldUnmute;
    } on Exception catch (e) {
      debugPrint('Error in shouldUnmuteMic: $e');
      return false;
    }
  }

  /// Get comprehensive playback info using Application Service
  Map<String, dynamic> getPlaybackInfo() {
    try {
      final coordinationState = _applicationService.getCoordinationState(
        isPlayingAI: _isPlayingAIAudio,
        isPlayingRing: _isPlayingRing,
        currentVoice: _currentVoice,
        currentAudioId: _currentlyPlayingAudioId,
        position: _playbackPosition,
        duration: _playbackDuration,
      );

      return {
        'isPlayingAIAudio': _isPlayingAIAudio,
        'isPlayingRing': _isPlayingRing,
        'playbackProgress': coordinationState.playbackProgress,
        'currentVoice': coordinationState.voiceConfiguration,
        'currentAudioId': coordinationState.activeAudioId,
        'playbackStatus': _playbackStatus,
        'duration': coordinationState.durationMs,
        'position': coordinationState.positionMs,
        'isAnyAudioActive': coordinationState.isAnyAudioActive,
      };
    } on Exception catch (e) {
      debugPrint('Error in getPlaybackInfo: $e');
      return {};
    }
  }

  /// Reset all playback state using Application Service
  Future<void> resetPlayback() async {
    try {
      final result = await _applicationService.resetAllPlayback();
      if (result.success) {
        _resetPlaybackState();
        notifyListeners();
        debugPrint('🔄 [AUDIO] Playback reset');
      } else {
        throw Exception(result.error);
      }
    } on Exception catch (e) {
      debugPrint('Error in resetPlayback: $e');
      rethrow;
    }
  }

  // Private helper methods
  void _initializeStreamListeners() {
    _positionSubscription = _audioPlayer.onPositionChanged.listen((
      final position,
    ) {
      _playbackPosition = position;
      if (_playbackDuration.inMilliseconds > 0) {
        _playbackProgress =
            position.inMilliseconds / _playbackDuration.inMilliseconds;
      }
      notifyListeners();
    });
    _durationSubscription = _audioPlayer.onDurationChanged.listen((
      final duration,
    ) {
      _playbackDuration = duration;
      notifyListeners();
    });
    _completionSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      _updateAudioState(false, 'completed');
      _currentlyPlayingAudioId = null;
      notifyListeners();
      debugPrint('✅ [AUDIO] Playback completed');
    });
  }

  void _updateAudioState(final bool playing, final String status) {
    _isPlayingAIAudio = playing;
    _playbackStatus = status;
    if (!playing) {
      _playbackProgress = 0.0;
      _playbackPosition = Duration.zero;
    }
  }

  void _updatePlaybackStatus(final String status) => _playbackStatus = status;

  void _resetPlaybackState() {
    _playbackProgress = 0.0;
    _playbackPosition = Duration.zero;
    _playbackDuration = Duration.zero;
    _currentlyPlayingAudioId = null;
    _updatePlaybackStatus('stopped');
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _completionSubscription?.cancel();
    super.dispose();
  }
}
