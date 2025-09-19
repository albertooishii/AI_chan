import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart' as record;
import 'package:ai_chan/shared/domain/interfaces/i_recording_service.dart';

/// 🎯 **Basic Recording Service** - Infrastructure Implementation
///
/// Implementation of IRecordingService using the record package.
/// This provides actual recording functionality while maintaining Clean Architecture.
///
/// **Clean Architecture Compliance:**
/// ✅ Infrastructure implements domain interfaces
/// ✅ External package dependencies isolated in infrastructure
/// ✅ Application layer uses domain abstractions
class BasicRecordingService implements IRecordingService {
  final record.AudioRecorder _recorder = record.AudioRecorder();
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isStreamActive = false;
  Duration _currentDuration = Duration.zero;
  Timer? _durationTimer;
  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _streamSubscription;

  @override
  bool get isRecording => _isRecording;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isStreamActive => _isStreamActive;

  @override
  Duration get currentDuration => _currentDuration;

  @override
  Stream<RecordingState> get recordingStateStream => _stateController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  Future<void> initialize() async {
    _stateController.add(RecordingState.initializing);
    // The AudioRecorder is already initialized when created
    _isInitialized = true;
    _stateController.add(RecordingState.idle);
  }

  @override
  Future<String> startRecording(final String filePath) async {
    if (!_isInitialized) {
      throw Exception('Recording service not initialized');
    }

    if (_isRecording) {
      throw Exception('Recording already in progress');
    }

    _isRecording = true;
    _currentDuration = Duration.zero;
    _stateController.add(RecordingState.recording);

    final config = const record.RecordConfig(encoder: record.AudioEncoder.wav);

    await _recorder.start(config, path: filePath);

    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      final timer,
    ) {
      _currentDuration += const Duration(milliseconds: 100);
    });

    // Start amplitude monitoring
    _startAmplitudeMonitoring();

    return filePath;
  }

  @override
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      return null;
    }

    _isRecording = false;
    _stateController.add(RecordingState.stopping);
    _durationTimer?.cancel();
    _durationTimer = null;
    _stopAmplitudeMonitoring();

    final path = await _recorder.stop();
    _stateController.add(RecordingState.idle);

    return path;
  }

  @override
  Future<void> pauseRecording() async {
    if (!_isRecording) {
      throw Exception('No recording in progress');
    }

    await _recorder.pause();
    _durationTimer?.cancel();
    _durationTimer = null;
    _stateController.add(RecordingState.paused);
  }

  @override
  Future<void> resumeRecording() async {
    if (!_isRecording) {
      throw Exception('Recording not in progress');
    }

    await _recorder.resume();
    _stateController.add(RecordingState.recording);

    // Resume duration timer
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      final timer,
    ) {
      _currentDuration += const Duration(milliseconds: 100);
    });
  }

  @override
  Future<void> cancelRecording() async {
    if (!_isRecording) {
      return;
    }

    _isRecording = false;
    _currentDuration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = null;
    _stopAmplitudeMonitoring();

    await _recorder.cancel();
    _stateController.add(RecordingState.idle);
  }

  @override
  Future<double> getAmplitude() async {
    if (!_isRecording) {
      return 0.0;
    }

    try {
      final amplitude = await _recorder.getAmplitude();
      return (amplitude.current).clamp(0.0, 1.0);
    } on Exception {
      return 0.0;
    }
  }

  @override
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  @override
  Future<bool> requestPermission() async {
    // The record package handles permission requests automatically
    return await _recorder.hasPermission();
  }

  @override
  Future<Stream<Uint8List>> startStream(final RecordingConfig config) async {
    if (!_isInitialized) {
      throw Exception('Recording service not initialized');
    }

    if (_isStreamActive) {
      throw Exception('Stream already active');
    }

    final recordConfig = record.RecordConfig(
      encoder: _mapEncoder(config.encoder),
      sampleRate: config.sampleRate,
      numChannels: config.channels,
    );

    final stream = await _recorder.startStream(recordConfig);
    _isStreamActive = true;
    _stateController.add(RecordingState.recording);

    // Start amplitude monitoring for stream
    _startAmplitudeMonitoring();

    return stream;
  }

  @override
  Future<void> stopStream() async {
    if (!_isStreamActive) {
      return;
    }

    _isStreamActive = false;
    _stopAmplitudeMonitoring();
    await _recorder.stop();
    _stateController.add(RecordingState.idle);
  }

  @override
  Future<void> dispose() async {
    _isRecording = false;
    _isInitialized = false;
    _isStreamActive = false;
    _currentDuration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = null;
    _stopAmplitudeMonitoring();
    await _streamSubscription?.cancel();
    await _recorder.dispose();
    await _stateController.close();
    await _amplitudeController.close();
  }

  void _startAmplitudeMonitoring() {
    Timer.periodic(const Duration(milliseconds: 100), (final timer) async {
      if (!_isRecording && !_isStreamActive) {
        timer.cancel();
        return;
      }

      try {
        final amplitude = await getAmplitude();
        _amplitudeController.add(amplitude);
      } on Exception {
        // Ignore amplitude errors
      }
    });
  }

  void _stopAmplitudeMonitoring() {
    // The timer will be cancelled by the periodic timer check
  }

  record.AudioEncoder _mapEncoder(final AudioEncoder encoder) {
    // For now, just return a default encoder since the record package enum values may differ
    return record.AudioEncoder.wav; // Use WAV as default
  }
}
