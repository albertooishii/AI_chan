import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:ai_chan/shared/domain/interfaces/i_recording_service.dart';
import '../services/call_recording_application_service.dart';

/// Call Recording Controller - Compact audio recording management
class CallRecordingController extends ChangeNotifier {
  CallRecordingController({required final IRecordingService recordingService})
    : _recordingService = recordingService {
    _applicationService = CallRecordingApplicationService(_recordingService);
  }

  // Dependencies
  final IRecordingService _recordingService;

  // Application Service for business logic
  late final CallRecordingApplicationService _applicationService;

  // Core recording state
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

    try {
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
      _micSub = flowResult.subscription;

      debugPrint('🎤 [REC] Recording started');
    } on Exception catch (e) {
      debugPrint('Error in startRecording: $e');
      rethrow;
    }
  }

  /// Stop recording and microphone using Application Service
  Future<void> stopRecording() async {
    if (!_isRecording && !_micStarted) return;

    try {
      _updateRecordingStatus('stopping');

      // Delegate complete stop flow to Application Service
      final flowResult = await _applicationService
          .coordinateCompleteRecordingStop(
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
      _micSub = null;
      _stopDurationTimer();

      debugPrint(
        '⏹️ [REC] Recording stopped (${flowResult.finalDuration?.inSeconds ?? 0}s, $_totalBytesRecorded bytes)',
      );
    } on Exception catch (e) {
      debugPrint('Error in stopRecording: $e');
      rethrow;
    }
  }

  /// Pause recording using Application Service
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    try {
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
    } on Exception catch (e) {
      debugPrint('Error in pauseRecording: $e');
      rethrow;
    }
  }

  /// Resume recording using Application Service
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    try {
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
    } on Exception catch (e) {
      debugPrint('Error in resumeRecording: $e');
      rethrow;
    }
  }

  /// Set target volume using Application Service
  void setTargetVolume(final double volume) {
    try {
      _targetVolume = _applicationService.coordinateVolumeSettings(volume);
    } on Exception catch (e) {
      debugPrint('Error in setTargetVolume: $e');
    }
  }

  /// Get recording info using Application Service
  Map<String, dynamic> getRecordingInfo() {
    try {
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
    } on Exception catch (e) {
      debugPrint('Error in getRecordingInfo: $e');
      return {};
    }
  }

  /// Check if audio input is available using Application Service
  Future<bool> checkAudioPermission() async {
    try {
      final permissionResult = await _applicationService
          .coordinatePermissionCheck();
      if (!permissionResult.hasPermission) {
        debugPrint('❌ [REC] ${permissionResult.error}');
      }
      return permissionResult.hasPermission;
    } on Exception catch (e) {
      debugPrint('Error in checkAudioPermission: $e');
      return false;
    }
  }

  /// Reset recording state
  void resetRecording() {
    try {
      _stopDurationTimer();
      _recordingStartTime = null;
      _recordingDuration = Duration.zero;
      _totalBytesRecorded = 0;
      _audioChunkCount = 0;
      _inputVolume = 0.0;
      _updateRecordingStatus('stopped');
      debugPrint('🔄 [REC] Recording state reset');
    } on Exception catch (e) {
      debugPrint('Error in resetRecording: $e');
    }
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
    _audioStreamController.close();
    _volumeController.close();
    super.dispose();
  }
}
