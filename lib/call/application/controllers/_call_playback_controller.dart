import 'package:flutter/material.dart';
import 'dart:async';
import 'package:ai_chan/shared/domain/interfaces/audio_playback_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';
import 'package:ai_chan/call/application/services/call_playback_application_service.dart';

/// Call Playback Controller - Compact audio management with Application Service
class CallPlaybackController extends ChangeNotifier
    with UIStateManagementMixin {
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
    await executeWithState(
      operation: () async {
        final result = await _applicationService.playAIAudio(
          audioPath,
          audioId: audioId,
        );
        if (result.success) {
          _currentlyPlayingAudioId = result.audioId;
          _updateAudioState(true, result.status ?? 'playing');
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to play AI audio',
    );
  }

  /// Stop AI audio using Application Service
  Future<void> stopAIAudio() async {
    await executeWithState(
      operation: () async {
        final result = await _applicationService.stopAIAudio();
        if (result.success) {
          _updateAudioState(false, result.status ?? 'stopped');
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to stop AI audio',
    );
  }

  /// Start ring using Application Service
  Future<void> startRing() async {
    if (_isPlayingRing) return;

    await executeWithState(
      operation: () async {
        final result = await _applicationService.manageRingTone(
          shouldRing: true,
        );
        if (result.success) {
          _isPlayingRing = true;
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to start ring',
    );
  }

  /// Stop ring using Application Service
  Future<void> stopRing() async {
    if (!_isPlayingRing) return;

    await executeWithState(
      operation: () async {
        final result = await _applicationService.manageRingTone(
          shouldRing: false,
        );
        if (result.success) {
          _isPlayingRing = false;
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to stop ring',
    );
  }

  /// Set volume levels (UI only)
  void setPlaybackVolume(final double volume) => executeSyncWithNotification(
    operation: () => _aiAudioVolume = volume.clamp(0.0, 1.0),
  );

  void setRingVolume(final double volume) => executeSyncWithNotification(
    operation: () => _ringVolume = volume.clamp(0.0, 1.0),
  );

  /// Update voice selection using Application Service
  void updateVoice(final String voice) => executeSyncWithNotification(
    operation: () {
      _currentVoice = _applicationService.resolveVoiceConfiguration(voice);
      debugPrint('🎤 [VOICE] Selected: $_currentVoice');
    },
  );

  /// Check if microphone should be unmuted using Application Service
  bool shouldUnmuteMic() {
    final recommendation = _applicationService.calculateUnmuteTiming(
      position: _playbackPosition,
      duration: _playbackDuration,
      isPlaying: _isPlayingAIAudio,
    );
    return recommendation.shouldUnmute;
  }

  /// Get comprehensive playback info using Application Service
  Map<String, dynamic> getPlaybackInfo() {
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
  }

  /// Reset all playback state using Application Service
  Future<void> resetPlayback() async {
    await executeWithState(
      operation: () async {
        final result = await _applicationService.resetAllPlayback();
        if (result.success) {
          _resetPlaybackState();
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to reset playback',
    );
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
