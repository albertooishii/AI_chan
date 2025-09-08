import 'dart:async';
import 'package:ai_chan/shared/domain/interfaces/audio_playback_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Application Service for Call Playback coordination
/// Handles audio playback orchestration following DDD patterns
class CallPlaybackApplicationService {
  CallPlaybackApplicationService({
    required final AudioPlaybackService audioPlayer,
    required final AudioPlaybackService ringPlayer,
  }) : _audioPlayer = audioPlayer,
       _ringPlayer = ringPlayer;

  final AudioPlaybackService _audioPlayer;
  final AudioPlaybackService _ringPlayer;

  /// Coordinate AI audio playback
  Future<CallPlaybackResult> playAIAudio(
    final String audioPath, {
    final String? audioId,
  }) async {
    try {
      // Stop any current audio first
      await _audioPlayer.stop();

      // Start new audio playback
      await _audioPlayer.play(audioPath);

      Log.d('Playing: ${audioId ?? audioPath}', tag: 'AUDIO');

      return CallPlaybackResult.success(
        audioId: audioId,
        audioPath: audioPath,
        status: 'playing',
      );
    } on Exception catch (e) {
      return CallPlaybackResult.failure(
        error: 'Failed to play AI audio: $e',
        operation: 'playAIAudio',
      );
    }
  }

  /// Coordinate AI audio stop
  Future<CallPlaybackResult> stopAIAudio() async {
    try {
      await _audioPlayer.stop();
      Log.d('Stopped AI audio', tag: 'AUDIO');

      return CallPlaybackResult.success(status: 'stopped');
    } on Exception catch (e) {
      return CallPlaybackResult.failure(
        error: 'Failed to stop AI audio: $e',
        operation: 'stopAIAudio',
      );
    }
  }

  /// Coordinate ring tone management
  Future<CallPlaybackResult> manageRingTone({
    required final bool shouldRing,
  }) async {
    try {
      if (shouldRing) {
        await _ringPlayer.play('assets/sounds/ring.mp3');
        Log.d('Ring tone started', tag: 'RING');
      } else {
        await _ringPlayer.stop();
        Log.d('Ring tone stopped', tag: 'RING');
      }

      return CallPlaybackResult.success(
        status: shouldRing ? 'ringing' : 'ring_stopped',
      );
    } on Exception catch (e) {
      return CallPlaybackResult.failure(
        error: 'Failed to manage ring tone: $e',
        operation: 'manageRingTone',
      );
    }
  }

  /// Calculate microphone unmute timing
  CallUnmuteRecommendation calculateUnmuteTiming({
    required final Duration position,
    required final Duration duration,
    required final bool isPlaying,
  }) {
    if (!isPlaying || duration == Duration.zero) {
      return CallUnmuteRecommendation(
        shouldUnmute: true,
        reason: 'No audio playing',
        progress: 0.0,
      );
    }

    const earlyUnmuteProgress = 0.8; // Unmute at 80% progress
    final progress = position.inMilliseconds / duration.inMilliseconds;
    final shouldUnmute = progress >= earlyUnmuteProgress;

    return CallUnmuteRecommendation(
      shouldUnmute: shouldUnmute,
      reason: shouldUnmute ? 'Near end of playback' : 'Audio still playing',
      progress: progress,
    );
  }

  /// Get comprehensive playback coordination state
  CallPlaybackCoordinationState getCoordinationState({
    required final bool isPlayingAI,
    required final bool isPlayingRing,
    required final String currentVoice,
    required final String? currentAudioId,
    required final Duration position,
    required final Duration duration,
  }) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return CallPlaybackCoordinationState(
      isAnyAudioActive: isPlayingAI || isPlayingRing,
      currentOperation: _determineCurrentOperation(isPlayingAI, isPlayingRing),
      voiceConfiguration: currentVoice,
      activeAudioId: currentAudioId,
      playbackProgress: progress,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
    );
  }

  /// Coordinate voice configuration
  String resolveVoiceConfiguration(final String? requestedVoice) {
    if (requestedVoice?.isNotEmpty == true) {
      return requestedVoice!;
    }
    return 'alloy'; // Default OpenAI voice
  }

  /// Reset all playback coordination
  Future<CallPlaybackResult> resetAllPlayback() async {
    try {
      await _audioPlayer.stop();
      await _ringPlayer.stop();

      Log.d('Reset complete', tag: 'AUDIO');

      return CallPlaybackResult.success(status: 'reset_complete');
    } on Exception catch (e) {
      return CallPlaybackResult.failure(
        error: 'Failed to reset playback: $e',
        operation: 'resetAllPlayback',
      );
    }
  }

  String _determineCurrentOperation(
    final bool isPlayingAI,
    final bool isPlayingRing,
  ) {
    if (isPlayingAI && isPlayingRing) return 'ai_and_ring';
    if (isPlayingAI) return 'ai_audio';
    if (isPlayingRing) return 'ring_tone';
    return 'idle';
  }
}

/// Result object for Call Playback operations
class CallPlaybackResult {
  CallPlaybackResult._({
    required this.success,
    this.error,
    this.operation,
    this.audioId,
    this.audioPath,
    this.status,
  });

  factory CallPlaybackResult.success({
    final String? audioId,
    final String? audioPath,
    final String? status,
  }) => CallPlaybackResult._(
    success: true,
    audioId: audioId,
    audioPath: audioPath,
    status: status,
  );

  factory CallPlaybackResult.failure({
    required final String error,
    required final String operation,
  }) =>
      CallPlaybackResult._(success: false, error: error, operation: operation);
  final bool success;
  final String? error;
  final String? operation;
  final String? audioId;
  final String? audioPath;
  final String? status;
}

/// Microphone unmute recommendation
class CallUnmuteRecommendation {
  CallUnmuteRecommendation({
    required this.shouldUnmute,
    required this.reason,
    required this.progress,
  });
  final bool shouldUnmute;
  final String reason;
  final double progress;
}

/// Call Playback coordination state
class CallPlaybackCoordinationState {
  CallPlaybackCoordinationState({
    required this.isAnyAudioActive,
    required this.currentOperation,
    required this.voiceConfiguration,
    this.activeAudioId,
    required this.playbackProgress,
    required this.positionMs,
    required this.durationMs,
  });
  final bool isAnyAudioActive;
  final String currentOperation;
  final String voiceConfiguration;
  final String? activeAudioId;
  final double playbackProgress;
  final int positionMs;
  final int durationMs;
}

/// Exception for Call Playback Application Service
class CallPlaybackApplicationException implements Exception {
  CallPlaybackApplicationException(this.message, this.operation);
  final String message;
  final String operation;

  @override
  String toString() =>
      'CallPlaybackApplicationException: $message (operation: $operation)';
}
