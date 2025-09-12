import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../interfaces/audio/i_audio_recorder_service.dart';
import '../../../../utils/log_utils.dart';

/// 🎯 Servicio centralizado de grabación de audio
/// Utiliza record package para capturar audio del micrófono
class CentralizedAudioRecorderService implements IAudioRecorderService {
  CentralizedAudioRecorderService._();

  static final CentralizedAudioRecorderService _instance =
      CentralizedAudioRecorderService._();
  static CentralizedAudioRecorderService get instance => _instance;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<List<int>> _audioDataController =
      StreamController<List<int>>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  bool _isRecording = false;
  String? _currentRecordingPath;
  Timer? _amplitudeTimer;

  @override
  Stream<List<int>> get audioDataStream => _audioDataController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<bool> hasPermissions() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      Log.d('[CentralizedAudioRecorder] Permisos de micrófono: $hasPermission');
      return hasPermission;
    } on Exception catch (e) {
      Log.e('[CentralizedAudioRecorder] ❌ Error verificando permisos: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      // Usar permission_handler para control más granular
      final status = await Permission.microphone.request();
      final hasPermission = status == PermissionStatus.granted;

      Log.d('[CentralizedAudioRecorder] Solicitud de permisos: $hasPermission');
      return hasPermission;
    } on Exception catch (e) {
      Log.e('[CentralizedAudioRecorder] ❌ Error solicitando permisos: $e');
      return false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final hasPermission = await hasPermissions();
      final isSupported = await _recorder.isEncoderSupported(AudioEncoder.wav);

      Log.d(
        '[CentralizedAudioRecorder] Disponibilidad - Permisos: $hasPermission, Soporte WAV: $isSupported',
      );
      return hasPermission && isSupported;
    } on Exception catch (e) {
      Log.e(
        '[CentralizedAudioRecorder] ❌ Error verificando disponibilidad: $e',
      );
      return false;
    }
  }

  @override
  Future<AudioRecordingResult> recordAudio({
    required final Duration duration,
    final int sampleRate = 16000,
    final String format = 'wav',
  }) async {
    try {
      if (_isRecording) {
        throw const AudioRecorderException('Ya hay una grabación en progreso');
      }

      if (!await hasPermissions()) {
        final granted = await requestPermissions();
        if (!granted) {
          throw const AudioPermissionException(
            'Permisos de micrófono denegados',
          );
        }
      }

      Log.d(
        '[CentralizedAudioRecorder] 🎤 Iniciando grabación por ${duration.inSeconds}s',
      );

      await startRecording(sampleRate: sampleRate, format: format);

      // Esperar la duración especificada
      await Future.delayed(duration);

      final result = await stopRecording();

      Log.d(
        '[CentralizedAudioRecorder] ✅ Grabación completada: ${result.sizeInBytes} bytes',
      );
      return result;
    } on AudioRecorderException {
      rethrow;
    } on Exception catch (e) {
      Log.e('[CentralizedAudioRecorder] ❌ Error en grabación: $e');
      throw AudioRecorderException(
        'Error durante la grabación',
        originalError: e,
      );
    }
  }

  @override
  Future<void> startRecording({
    final int sampleRate = 16000,
    final String format = 'wav',
  }) async {
    try {
      if (_isRecording) {
        throw const AudioRecorderException('Ya hay una grabación en progreso');
      }

      if (!await hasPermissions()) {
        final granted = await requestPermissions();
        if (!granted) {
          throw const AudioPermissionException(
            'Permisos de micrófono denegados',
          );
        }
      }

      // Crear archivo temporal
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'recording_${DateTime.now().millisecondsSinceEpoch}.$format';
      _currentRecordingPath = '${tempDir.path}/$fileName';

      // Configurar grabación
      final config = RecordConfig(
        encoder: _getAudioEncoder(format),
        sampleRate: sampleRate,
        numChannels: 1, // Mono para STT
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

      await _recorder.start(config, path: _currentRecordingPath!);
      _isRecording = true;

      // Iniciar monitoreo de amplitud
      _startAmplitudeMonitoring();

      Log.d(
        '[CentralizedAudioRecorder] 🎤 Grabación iniciada: $_currentRecordingPath',
      );
    } on AudioRecorderException {
      rethrow;
    } on Exception catch (e) {
      Log.e('[CentralizedAudioRecorder] ❌ Error iniciando grabación: $e');
      throw AudioRecorderException(
        'Error iniciando grabación',
        originalError: e,
      );
    }
  }

  @override
  Future<AudioRecordingResult> stopRecording() async {
    try {
      if (!_isRecording) {
        throw const AudioRecorderException('No hay grabación activa');
      }

      final recordingPath = await _recorder.stop();
      _isRecording = false;

      // Detener monitoreo de amplitud
      _stopAmplitudeMonitoring();

      if (recordingPath == null || _currentRecordingPath == null) {
        throw const AudioRecorderException('Error: ruta de grabación inválida');
      }

      // Leer datos del archivo
      final file = File(_currentRecordingPath!);
      if (!file.existsSync()) {
        throw const AudioRecorderException(
          'Archivo de grabación no encontrado',
        );
      }

      final audioData = await file.readAsBytes();

      // Calcular duración aproximada (para WAV mono 16kHz)
      final durationMs =
          (audioData.length / (16000 * 2)) * 1000; // 16kHz * 2 bytes per sample
      final duration = Duration(milliseconds: durationMs.round());

      Log.d(
        '[CentralizedAudioRecorder] ✅ Grabación detenida: ${audioData.length} bytes, ${duration.inSeconds}s',
      );

      final result = AudioRecordingResult(
        audioData: audioData,
        format: 'wav',
        duration: duration,
        sampleRate: 16000,
        filePath: _currentRecordingPath,
      );

      // Limpiar archivo temporal después de crear el resultado
      _cleanupCurrentRecording();

      return result;
    } on AudioRecorderException {
      rethrow;
    } on Exception catch (e) {
      Log.e('[CentralizedAudioRecorder] ❌ Error deteniendo grabación: $e');
      throw AudioRecorderException(
        'Error deteniendo grabación',
        originalError: e,
      );
    }
  }

  @override
  Future<void> cancelRecording() async {
    try {
      if (!_isRecording) {
        return; // No hay nada que cancelar
      }

      await _recorder.stop();
      _isRecording = false;

      _stopAmplitudeMonitoring();
      _cleanupCurrentRecording();

      Log.d('[CentralizedAudioRecorder] 🚫 Grabación cancelada');
    } on Exception catch (e) {
      Log.e('[CentralizedAudioRecorder] ❌ Error cancelando grabación: $e');
    }
  }

  /// Obtener encoder según formato
  AudioEncoder _getAudioEncoder(final String format) {
    switch (format.toLowerCase()) {
      case 'wav':
        return AudioEncoder.wav;
      case 'aac':
        return AudioEncoder.aacLc;
      case 'm4a':
        return AudioEncoder.aacLc;
      case 'mp3':
        return AudioEncoder.wav; // Fallback a WAV si no hay soporte directo
      default:
        return AudioEncoder.wav;
    }
  }

  /// Iniciar monitoreo de amplitud
  void _startAmplitudeMonitoring() {
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
      final timer,
    ) async {
      if (_isRecording) {
        try {
          final amplitude = await _recorder.getAmplitude();
          // Convertir de Amplitude a double (0.0 - 1.0)
          final normalizedAmplitude =
              amplitude.current.clamp(-60.0, 0.0) / -60.0;
          _amplitudeController.add(normalizedAmplitude);
        } on Exception catch (e) {
          Log.w('[CentralizedAudioRecorder] Error obteniendo amplitud: $e');
        }
      }
    });
  }

  /// Detener monitoreo de amplitud
  void _stopAmplitudeMonitoring() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _amplitudeController.add(0.0); // Reset amplitud
  }

  /// Limpiar grabación actual
  void _cleanupCurrentRecording() {
    if (_currentRecordingPath != null) {
      try {
        final file = File(_currentRecordingPath!);
        if (file.existsSync()) {
          file.deleteSync();
          Log.d(
            '[CentralizedAudioRecorder] Archivo temporal eliminado: $_currentRecordingPath',
          );
        }
      } on Exception catch (e) {
        Log.w(
          '[CentralizedAudioRecorder] Error eliminando archivo temporal: $e',
        );
      } finally {
        _currentRecordingPath = null;
      }
    }
  }

  /// Limpiar recursos
  void dispose() {
    cancelRecording();
    _audioDataController.close();
    _amplitudeController.close();
    _recorder.dispose();
  }
}
