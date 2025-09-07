import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';
import '../services/call_recording_application_service.dart';

/// Call Recording Controller - Compact audio recording management
class CallRecordingController extends ChangeNotifier
    with UIStateManagementMixin {
  CallRecordingController()
    : _applicationService = CallRecordingApplicationService();

  // Application Service for business logic
  final CallRecordingApplicationService _applicationService;

  // Core recording state
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  bool _isRecording = false,
      _isPaused = false,
      _micStarted = false,
      _startingMic = false;
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  String _recordingStatus = 'stopped';
  double _inputVolume = 0.0, _targetVolume = 1.0;
  int _totalBytesRecorded = 0, _audioChunkCount = 0;

  // Streams
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();

  // Getters - consolidated
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get micStarted => _micStarted;
  bool get startingMic => _startingMic;
  DateTime? get recordingStartTime => _recordingStartTime;
  Duration get recordingDuration => _recordingDuration;
  String get recordingStatus => _recordingStatus;
  double get inputVolume => _inputVolume;
  double get targetVolume => _targetVolume;
  int get totalBytesRecorded => _totalBytesRecorded;
  int get audioChunkCount => _audioChunkCount;
  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<double> get volumeStream => _volumeController.stream;
  bool get canStartRecording => !_isRecording && !_startingMic;
  bool get canStopRecording => _isRecording || _micStarted;

  /// Start microphone and recording using Application Service
  Future<void> startRecording() async {
    if (_isRecording || _startingMic) return;

    await executeWithState(
      operation: () async {
        _startingMic = true;
        _updateRecordingStatus('starting');

        // Delegate complete flow to Application Service
        final flowResult = await _applicationService
            .coordinateCompleteRecordingStart(
              onStatusUpdate: _updateRecordingStatus,
              onVolumeUpdate: (final volume) {
                _inputVolume = volume;
                _volumeController.add(volume);
              },
              onAudioStream: () => _audioStreamController.stream,
              onRecordingStarted: (final startTime) {
                _recordingStartTime = startTime;
                _isRecording = true;
                _micStarted = true;
                _startDurationTimer();
              },
              onDurationUpdate: (final duration) {
                _recordingDuration = duration;
              },
            );

        if (!flowResult.success) {
          throw Exception(flowResult.error);
        }

        // Update state with Application Service results
        _recorder = flowResult.recorder;
        _micSub = flowResult.subscription;

        debugPrint('🎤 [REC] Recording started');
      },
      errorMessage: 'Failed to start recording',
    );
  }

  /// Stop recording and microphone using Application Service
  Future<void> stopRecording() async {
    if (!_isRecording && !_micStarted) return;

    await executeWithState(
      operation: () async {
        _updateRecordingStatus('stopping');

        // Delegate complete stop flow to Application Service
        final flowResult = await _applicationService
            .coordinateCompleteRecordingStop(
              recorder: _recorder,
              subscription: _micSub,
              startTime: _recordingStartTime,
              onStatusUpdate: _updateRecordingStatus,
              onFinalDuration: (final duration) {
                _recordingDuration = duration;
              },
            );

        if (!flowResult.success) {
          throw Exception(flowResult.error);
        }

        // Reset state
        _isRecording = false;
        _micStarted = false;
        _isPaused = false;
        _recordingStartTime = null;
        _recorder = null;
        _micSub = null;
        _stopDurationTimer();

        debugPrint(
          '⏹️ [REC] Recording stopped (${flowResult.finalDuration?.inSeconds ?? 0}s, $_totalBytesRecorded bytes)',
        );
      },
      errorMessage: 'Failed to stop recording',
    );
  }

  /// Pause recording using Application Service
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    await executeWithState(
      operation: () async {
        final result = _applicationService.coordinatePauseResume(
          isPausing: true,
          isCurrentlyRecording: _isRecording,
          isCurrentlyPaused: _isPaused,
        );

        if (result.success) {
          _isPaused = true;
          _updateRecordingStatus(result.status);
          _stopDurationTimer();
          debugPrint('⏸️ [REC] Recording paused');
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to pause recording',
    );
  }

  /// Resume recording using Application Service
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    await executeWithState(
      operation: () async {
        final result = _applicationService.coordinatePauseResume(
          isPausing: false,
          isCurrentlyRecording: _isRecording,
          isCurrentlyPaused: _isPaused,
        );

        if (result.success) {
          _isPaused = false;
          _updateRecordingStatus(result.status);
          _startDurationTimer();
          debugPrint('▶️ [REC] Recording resumed');
        } else {
          throw Exception(result.error);
        }
      },
      errorMessage: 'Failed to resume recording',
    );
  }

  /// Set target volume using Application Service
  void setTargetVolume(final double volume) => executeSyncWithNotification(
    operation: () =>
        _targetVolume = _applicationService.coordinateVolumeSettings(volume),
  );

  /// Get recording info using Application Service
  Map<String, dynamic> getRecordingInfo() {
    final stateResult = _applicationService.coordinateRecordingState(
      isRecording: _isRecording,
      isPaused: _isPaused,
      micStarted: _micStarted,
      startingMic: _startingMic,
      recordingDuration: _recordingDuration,
      status: _recordingStatus,
      inputVolume: _inputVolume,
      targetVolume: _targetVolume,
      totalBytes: _totalBytesRecorded,
      chunkCount: _audioChunkCount,
      startTime: _recordingStartTime,
    );
    return stateResult.recordingInfo;
  }

  /// Check if audio input is available using Application Service
  Future<bool> checkAudioPermission() async {
    final permissionResult = await _applicationService
        .coordinatePermissionCheck();
    if (!permissionResult.hasPermission) {
      debugPrint('❌ [REC] ${permissionResult.error}');
    }
    return permissionResult.hasPermission;
  }

  /// Reset recording state
  void resetRecording() {
    executeSyncWithNotification(
      operation: () {
        _stopDurationTimer();
        _recordingStartTime = null;
        _recordingDuration = Duration.zero;
        _totalBytesRecorded = 0;
        _audioChunkCount = 0;
        _inputVolume = 0.0;
        _updateRecordingStatus('stopped');
        debugPrint('🔄 [REC] Recording state reset');
      },
    );
  }

  // Private helper methods - streamlined

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_recordingStartTime != null && _isRecording && !_isPaused) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        notifyListeners();
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _updateRecordingStatus(final String status) => _recordingStatus = status;

  @override
  void dispose() {
    _stopDurationTimer();
    _micSub?.cancel();
    _recorder?.dispose();
    _audioStreamController.close();
    _volumeController.close();
    super.dispose();
  }
}
