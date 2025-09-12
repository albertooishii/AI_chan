import 'dart:async';
import 'dart:math' as math;

/// 🎯 Servicio centralizado para manejo de amplitud del micrófono
/// En el futuro integrará con STT real para obtener niveles de audio reales
class CentralizedMicrophoneAmplitudeService {
  factory CentralizedMicrophoneAmplitudeService() => _instance;
  CentralizedMicrophoneAmplitudeService._internal();
  static final CentralizedMicrophoneAmplitudeService _instance =
      CentralizedMicrophoneAmplitudeService._internal();

  static CentralizedMicrophoneAmplitudeService get instance => _instance;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Timer? _simulationTimer;
  bool _isListening = false;

  /// Stream de amplitud (0.0 - 1.0)
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Estado actual de escucha
  bool get isListening => _isListening;

  /// Iniciar la simulación de amplitud
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      final timer,
    ) {
      final amplitude = _generateRealisticAmplitude();
      _amplitudeController.add(amplitude);
    });
  }

  /// Detener la simulación
  void stopListening() {
    _isListening = false;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _amplitudeController.add(0.0);
  }

  /// Generar amplitud realista simulando habla humana
  double _generateRealisticAmplitude() {
    final random = math.Random();

    // Patrón base de habla (ondas senoidales con variaciones)
    final baseWave =
        math.sin(DateTime.now().millisecondsSinceEpoch / 500) * 0.3;

    // Agregar spikes ocasionales (consonantes)
    final spike = random.nextDouble() < 0.15 ? random.nextDouble() * 0.6 : 0.0;

    // Ruido de fondo mínimo
    final background = random.nextDouble() * 0.1;

    // Pausas ocasionales (respiración)
    final pause = random.nextDouble() < 0.05 ? -0.8 : 0.0;

    final amplitude = (baseWave.abs() + spike + background + pause).clamp(
      0.0,
      1.0,
    );

    return amplitude;
  }

  /// Limpiar recursos
  void dispose() {
    _simulationTimer?.cancel();
    _amplitudeController.close();
  }
}
