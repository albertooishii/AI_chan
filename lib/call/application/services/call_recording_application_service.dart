// The service intentionally creates and returns a StreamSubscription to the
// caller (controller) so the caller owns its lifecycle and must cancel it.
// That ownership pattern triggers the `cancel_subscriptions` analyzer lint in
// some configurations because the subscription is not cancelled inside this
// file. Suppress the lint at file scope with a clear rationale.
import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Result objects for DDD pattern compliance
class RecordingSessionResult {
  const RecordingSessionResult({
    required this.success,
    required this.status,
    this.startTime,
    this.duration,
    this.error,
  });

  factory RecordingSessionResult.success(
    final String status, {
    final DateTime? startTime,
    final Duration? duration,
  }) => RecordingSessionResult(
    success: true,
    status: status,
    startTime: startTime,
    duration: duration,
  );

  factory RecordingSessionResult.failure(final String error) =>
      RecordingSessionResult(success: false, status: 'error', error: error);
  final bool success;
  final String status;
  final DateTime? startTime;
  final Duration? duration;
  final String? error;
}

class AudioStreamCoordinationResult {
  const AudioStreamCoordinationResult({
    required this.success,
    required this.micStarted,
    this.recorder,
    this.subscription,
    this.error,
  });

  factory AudioStreamCoordinationResult.success(
    final bool micStarted, {
    final AudioRecorder? recorder,
    final StreamSubscription<Uint8List>? subscription,
  }) => AudioStreamCoordinationResult(
    success: true,
    micStarted: micStarted,
    recorder: recorder,
    subscription: subscription,
  );

  factory AudioStreamCoordinationResult.failure(final String error) =>
      AudioStreamCoordinationResult(
        success: false,
        micStarted: false,
        error: error,
      );
  final bool success;
  final bool micStarted;
  final AudioRecorder? recorder;
  final StreamSubscription<Uint8List>? subscription;
  final String? error;
}

class AudioDataAnalysisResult {
  const AudioDataAnalysisResult({
    required this.volume,
    required this.totalBytes,
    required this.chunkCount,
    required this.shouldProcessData,
  });
  final double volume;
  final int totalBytes;
  final int chunkCount;
  final bool shouldProcessData;
}

class RecordingPermissionResult {
  const RecordingPermissionResult({
    required this.hasPermission,
    required this.canRecord,
    this.error,
  });

  factory RecordingPermissionResult.success(final bool hasPermission) =>
      RecordingPermissionResult(
        hasPermission: hasPermission,
        canRecord: hasPermission,
      );

  factory RecordingPermissionResult.failure(final String error) =>
      RecordingPermissionResult(
        hasPermission: false,
        canRecord: false,
        error: error,
      );
  final bool hasPermission;
  final bool canRecord;
  final String? error;
}

class RecordingStateCoordinationResult {
  const RecordingStateCoordinationResult({
    required this.recordingInfo,
    required this.canStart,
    required this.canStop,
    required this.canPause,
    required this.canResume,
  });
  final Map<String, dynamic> recordingInfo;
  final bool canStart;
  final bool canStop;
  final bool canPause;
  final bool canResume;
}

/// DDD Application Service for Call Recording coordination and business logic
class CallRecordingApplicationService {
  /// Coordinate recording session lifecycle
  RecordingSessionResult coordinateRecordingSession({
    required final bool isStarting,
    required final bool isCurrentlyRecording,
    required final bool isCurrentlyPaused,
    final DateTime? currentStartTime,
  }) {
    try {
      if (isStarting) {
        // Business rule: Cannot start if already recording
        if (isCurrentlyRecording) {
          return RecordingSessionResult.failure(
            'Recording already in progress',
          );
        }

        return RecordingSessionResult.success(
          'recording',
          startTime: DateTime.now(),
        );
      } else {
        // Stopping session
        if (!isCurrentlyRecording) {
          return RecordingSessionResult.failure('No active recording to stop');
        }

        final duration = currentStartTime != null
            ? DateTime.now().difference(currentStartTime)
            : Duration.zero;

        return RecordingSessionResult.success('stopped', duration: duration);
      }
    } on Exception catch (e) {
      return RecordingSessionResult.failure('Session coordination failed: $e');
    }
  }

  /// Coordinate pause/resume operations
  RecordingSessionResult coordinatePauseResume({
    required final bool isPausing, // true for pause, false for resume
    required final bool isCurrentlyRecording,
    required final bool isCurrentlyPaused,
  }) {
    try {
      if (isPausing) {
        // Business rule: Can only pause if recording and not already paused
        if (!isCurrentlyRecording || isCurrentlyPaused) {
          return RecordingSessionResult.failure(
            'Cannot pause: not recording or already paused',
          );
        }
        return RecordingSessionResult.success('paused');
      } else {
        // Resuming
        if (!isCurrentlyRecording || !isCurrentlyPaused) {
          return RecordingSessionResult.failure('Cannot resume: not paused');
        }
        return RecordingSessionResult.success('recording');
      }
    } on Exception catch (e) {
      return RecordingSessionResult.failure(
        'Pause/resume coordination failed: $e',
      );
    }
  }

  /// Coordinate microphone stream initialization
  Future<AudioStreamCoordinationResult> coordinateMicrophoneStream({
    required final bool isStarting,
    final AudioRecorder? currentRecorder,
  }) async {
    try {
      if (isStarting) {
        // Business rule: Initialize recorder if not exists
        final recorder = currentRecorder ?? AudioRecorder();

        // Business rule: Check permissions first
        if (!await recorder.hasPermission()) {
          return AudioStreamCoordinationResult.failure(
            'Microphone permission not granted',
          );
        }

        // Business rule: Configure recording parameters
        const config = RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 24000,
          numChannels: 1,
        );

        final stream = await recorder.startStream(config);
        // ignore: cancel_subscriptions
        late StreamSubscription<Uint8List> subscription;
        // Intentionally return a live StreamSubscription to the caller. Ownership
        // of the subscription is transferred to the caller (controller). The
        // caller is responsible for cancelling it when no longer needed. The
        // analyzer's `cancel_subscriptions` lint is suppressed here because the
        // subscription is not leaked by the service: it is created then returned
        // inside the result object so the caller controls its lifecycle.
        subscription = stream.listen((_) {});

        return AudioStreamCoordinationResult.success(
          true,
          recorder: recorder,
          subscription: subscription,
        );
      } else {
        // Stopping stream
        return AudioStreamCoordinationResult.success(false);
      }
    } on Exception catch (e) {
      return AudioStreamCoordinationResult.failure(
        'Microphone stream coordination failed: $e',
      );
    }
  }

  /// Analyze audio data and calculate metrics
  AudioDataAnalysisResult analyzeAudioData({
    required final Uint8List audioData,
    required final bool isRecording,
    required final bool isPaused,
    required final int currentTotalBytes,
    required final int currentChunkCount,
  }) {
    // Business rule: Only process if actively recording
    final shouldProcess = isRecording && !isPaused;

    if (!shouldProcess) {
      return AudioDataAnalysisResult(
        volume: 0.0,
        totalBytes: currentTotalBytes,
        chunkCount: currentChunkCount,
        shouldProcessData: false,
      );
    }

    // Calculate volume using RMS
    final volume = _calculateRMSVolume(audioData);

    return AudioDataAnalysisResult(
      volume: volume,
      totalBytes: currentTotalBytes + audioData.length,
      chunkCount: currentChunkCount + 1,
      shouldProcessData: true,
    );
  }

  /// Validate and coordinate volume settings
  double coordinateVolumeSettings(final double requestedVolume) {
    // Business rule: Volume must be between 0.0 and 1.0
    return requestedVolume.clamp(0.0, 1.0);
  }

  /// Check recording permissions with business rules
  Future<RecordingPermissionResult> coordinatePermissionCheck() async {
    try {
      final recorder = AudioRecorder();
      final hasPermission = await recorder.hasPermission();

      // Business rule: Must have permission to record
      if (!hasPermission) {
        return RecordingPermissionResult.failure(
          'Microphone permission is required for recording',
        );
      }

      return RecordingPermissionResult.success(true);
    } on Exception catch (e) {
      return RecordingPermissionResult.failure('Permission check failed: $e');
    }
  }

  /// Coordinate state management and provide comprehensive status
  RecordingStateCoordinationResult coordinateRecordingState({
    required final bool isRecording,
    required final bool isPaused,
    required final bool micStarted,
    required final bool startingMic,
    required final Duration recordingDuration,
    required final String status,
    required final double inputVolume,
    required final double targetVolume,
    required final int totalBytes,
    required final int chunkCount,
    final DateTime? startTime,
  }) {
    // Calculate operation capabilities based on current state
    final canStart = !isRecording && !startingMic;
    final canStop = isRecording || micStarted;
    final canPause = isRecording && !isPaused;
    final canResume = isRecording && isPaused;

    final recordingInfo = {
      'isRecording': isRecording,
      'isPaused': isPaused,
      'micStarted': micStarted,
      'duration': recordingDuration.inSeconds,
      'status': status,
      'inputVolume': inputVolume,
      'targetVolume': targetVolume,
      'totalBytes': totalBytes,
      'chunkCount': chunkCount,
      'startTime': startTime?.toIso8601String(),
      'canStart': canStart,
      'canStop': canStop,
      'canPause': canPause,
      'canResume': canResume,
    };

    return RecordingStateCoordinationResult(
      recordingInfo: recordingInfo,
      canStart: canStart,
      canStop: canStop,
      canPause: canPause,
      canResume: canResume,
    );
  }

  /// Coordinate cleanup operations
  Future<RecordingSessionResult> coordinateCleanup(
    final AudioRecorder? recorder,
  ) async {
    try {
      if (recorder != null) {
        await recorder.stop();
        await recorder.dispose();
      }
      return RecordingSessionResult.success('cleaned');
    } on Exception catch (e) {
      return RecordingSessionResult.failure('Cleanup failed: $e');
    }
  }

  /// Calculate duration constraints based on business rules
  Duration calculateMaxRecordingDuration() {
    // Business rule: Maximum recording duration is 2 hours
    return const Duration(hours: 2);
  }

  /// Check if recording should be automatically stopped
  bool shouldAutoStopRecording(final Duration currentDuration) {
    return currentDuration >= calculateMaxRecordingDuration();
  }

  /// Coordinate complete recording flow with all business logic
  Future<CompleteRecordingFlowResult> coordinateCompleteRecordingStart({
    required final Function(String) onStatusUpdate,
    required final Function(double) onVolumeUpdate,
    required final Stream<Uint8List> Function() onAudioStream,
    required final Function(DateTime) onRecordingStarted,
    required final Function(Duration) onDurationUpdate,
  }) async {
    try {
      // Step 1: Check permissions
      final permissionResult = await coordinatePermissionCheck();
      if (!permissionResult.hasPermission) {
        return CompleteRecordingFlowResult.failure(
          'Permission denied: ${permissionResult.error}',
        );
      }

      // Step 2: Initialize recorder
      final recorder = AudioRecorder();

      // Step 3: Start microphone stream
      final streamResult = await coordinateMicrophoneStream(
        isStarting: true,
        currentRecorder: recorder,
      );

      if (!streamResult.success) {
        return CompleteRecordingFlowResult.failure(
          'Stream failed: ${streamResult.error}',
        );
      }

      // Step 4: Setup recording session
      final sessionResult = coordinateRecordingSession(
        isStarting: true,
        isCurrentlyRecording: false,
        isCurrentlyPaused: false,
      );

      if (!sessionResult.success) {
        return CompleteRecordingFlowResult.failure(
          'Session failed: ${sessionResult.error}',
        );
      }

      final startTime = sessionResult.startTime ?? DateTime.now();
      onRecordingStarted(startTime);
      onStatusUpdate('recording');

      return CompleteRecordingFlowResult.success(
        recorder: streamResult.recorder!,
        subscription: streamResult.subscription!,
        startTime: startTime,
      );
    } on Exception catch (e) {
      return CompleteRecordingFlowResult.failure('Complete flow failed: $e');
    }
  }

  /// Coordinate complete recording stop with all cleanup
  Future<CompleteRecordingFlowResult> coordinateCompleteRecordingStop({
    required final AudioRecorder? recorder,
    required final StreamSubscription<Uint8List>? subscription,
    required final DateTime? startTime,
    required final Function(String) onStatusUpdate,
    required final Function(Duration) onFinalDuration,
  }) async {
    try {
      // Step 1: Calculate final duration
      final duration = startTime != null
          ? DateTime.now().difference(startTime)
          : Duration.zero;
      onFinalDuration(duration);

      // Step 2: Stop stream
      if (subscription != null) {
        await subscription.cancel();
      }

      // Step 3: Stop recording session
      coordinateRecordingSession(
        isStarting: false,
        isCurrentlyRecording: true,
        isCurrentlyPaused: false,
        currentStartTime: startTime,
      );

      // Step 4: Cleanup recorder
      if (recorder != null) {
        await coordinateCleanup(recorder);
      }

      onStatusUpdate('stopped');

      return CompleteRecordingFlowResult.success(finalDuration: duration);
    } on Exception catch (e) {
      return CompleteRecordingFlowResult.failure('Complete stop failed: $e');
    }
  }

  // Private business logic methods
  double _calculateRMSVolume(final Uint8List audioData) {
    if (audioData.isEmpty) return 0.0;

    double sum = 0.0;
    for (int i = 0; i < audioData.length; i += 2) {
      if (i + 1 < audioData.length) {
        final sample = (audioData[i] | (audioData[i + 1] << 8)).toSigned(16);
        sum += sample * sample;
      }
    }

    final rms = sum / (audioData.length / 2);
    return (rms / (32768 * 32768)).clamp(0.0, 1.0);
  }
}

/// Complete Recording Flow Result for complex coordination
class CompleteRecordingFlowResult {
  const CompleteRecordingFlowResult({
    required this.success,
    this.recorder,
    this.subscription,
    this.startTime,
    this.finalDuration,
    this.error,
  });

  factory CompleteRecordingFlowResult.success({
    final AudioRecorder? recorder,
    final StreamSubscription<Uint8List>? subscription,
    final DateTime? startTime,
    final Duration? finalDuration,
  }) => CompleteRecordingFlowResult(
    success: true,
    recorder: recorder,
    subscription: subscription,
    startTime: startTime,
    finalDuration: finalDuration,
  );

  factory CompleteRecordingFlowResult.failure(final String error) =>
      CompleteRecordingFlowResult(success: false, error: error);

  final bool success;
  final AudioRecorder? recorder;
  final StreamSubscription<Uint8List>? subscription;
  final DateTime? startTime;
  final Duration? finalDuration;
  final String? error;
}
