import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';

/// Call Audio Controller - Manages audio processing for calls
class CallAudioController extends ChangeNotifier with UIStateManagementMixin {
  CallAudioController();

  // AGC settings
  bool _enableMicAutoGain = true;
  double _agcTargetRms = 0.15;
  double _agcMaxGain = 4.0;
  double _agcNoiseFloorRms = 0.0;
  static const double _agcNoiseFloorAlpha = 0.1;

  // Filter state
  double _hpPrevIn = 0.0;
  double _hpPrevOut = 0.0;
  double _currentVolumeLevel = 0.0;
  bool _isMuted = false;
  double _micGain = 1.0;

  // Getters
  bool get enableMicAutoGain => _enableMicAutoGain;
  double get agcTargetRms => _agcTargetRms;
  double get agcMaxGain => _agcMaxGain;
  double get currentVolumeLevel => _currentVolumeLevel;
  bool get isMuted => _isMuted;
  double get micGain => _micGain;

  /// Process audio data with enhancements
  Uint8List processAudioData(final Uint8List audioData) {
    if (_isMuted || audioData.isEmpty) return Uint8List(0);

    try {
      // Convert to Float64List for processing
      final samples = _bytesToSamples(audioData);
      final processed = _applyAudioProcessing(samples);
      return _samplesToBytes(processed);
    } on Exception catch (e) {
      debugPrint('🎵 [AUDIO] Processing error: $e');
      return audioData; // Return original on error
    }
  }

  /// Configure AGC settings
  void configureAGC({
    final bool? enabled,
    final double? targetRms,
    final double? maxGain,
  }) {
    executeSyncWithNotification(
      operation: () {
        if (enabled != null) _enableMicAutoGain = enabled;
        if (targetRms != null) _agcTargetRms = targetRms.clamp(0.0, 1.0);
        if (maxGain != null) _agcMaxGain = maxGain.clamp(1.0, 10.0);
      },
    );
  }

  /// Set mute state
  void setMuted(final bool muted) {
    executeSyncWithNotification(operation: () => _isMuted = muted);
  }

  /// Set microphone gain
  void setMicGain(final double gain) {
    executeSyncWithNotification(
      operation: () => _micGain = gain.clamp(0.0, 5.0),
    );
  }

  /// Update volume level for UI
  void updateVolumeLevel(final double level) {
    executeSyncWithNotification(
      operation: () => _currentVolumeLevel = level.clamp(0.0, 1.0),
    );
  }

  /// Reset audio state
  void reset() {
    executeSyncWithNotification(
      operation: () {
        _hpPrevIn = 0.0;
        _hpPrevOut = 0.0;
        _currentVolumeLevel = 0.0;
        _agcNoiseFloorRms = 0.0;
      },
    );
  }

  // Private helpers
  Float64List _bytesToSamples(final Uint8List bytes) {
    final samples = Float64List(bytes.length ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      final sample = (bytes[i * 2] | (bytes[i * 2 + 1] << 8)).toSigned(16);
      samples[i] = sample / 32768.0;
    }
    return samples;
  }

  Uint8List _samplesToBytes(final Float64List samples) {
    final bytes = Uint8List(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final sample = (samples[i] * 32767).round().clamp(-32768, 32767);
      bytes[i * 2] = sample & 0xFF;
      bytes[i * 2 + 1] = (sample >> 8) & 0xFF;
    }
    return bytes;
  }

  Float64List _applyAudioProcessing(final Float64List samples) {
    // Apply gain
    var processed = Float64List.fromList(
      samples.map((final s) => s * _micGain).toList(),
    );

    // Apply high-pass filter
    processed = _applyHighPassFilter(processed);

    // Apply AGC if enabled
    if (_enableMicAutoGain) {
      processed = _applyAGC(processed);
    }

    // Update volume level for UI
    final rms = _calculateRMS(processed);
    updateVolumeLevel(rms);

    return processed;
  }

  Float64List _applyHighPassFilter(final Float64List samples) {
    const cutoffFreq = 80.0; // Hz
    const sampleRate = 16000.0; // Hz
    final rc = 1.0 / (2.0 * math.pi * cutoffFreq);
    final dt = 1.0 / sampleRate;
    final alpha = rc / (rc + dt);

    final filtered = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      final output = alpha * (_hpPrevOut + samples[i] - _hpPrevIn);
      filtered[i] = output;
      _hpPrevIn = samples[i];
      _hpPrevOut = output;
    }
    return filtered;
  }

  Float64List _applyAGC(final Float64List samples) {
    final rms = _calculateRMS(samples);
    _updateNoiseFloor(rms);

    if (rms <= _agcNoiseFloorRms) return samples;

    final targetGain = _agcTargetRms / rms;
    final clampedGain = targetGain.clamp(0.1, _agcMaxGain);

    return Float64List.fromList(
      samples.map((final s) => s * clampedGain).toList(),
    );
  }

  double _calculateRMS(final Float64List samples) {
    if (samples.isEmpty) return 0.0;
    final sumSquares = samples.fold(0.0, (final sum, final s) => sum + s * s);
    return math.sqrt(sumSquares / samples.length);
  }

  void _updateNoiseFloor(final double rms) {
    _agcNoiseFloorRms =
        _agcNoiseFloorAlpha * rms +
        (1.0 - _agcNoiseFloorAlpha) * _agcNoiseFloorRms;
  }

  Map<String, dynamic> get audioInfo => {
    'agcEnabled': _enableMicAutoGain,
    'targetRms': _agcTargetRms,
    'maxGain': _agcMaxGain,
    'currentVolume': _currentVolumeLevel,
    'isMuted': _isMuted,
    'micGain': _micGain,
    'noiseFloor': _agcNoiseFloorRms,
  };
}
