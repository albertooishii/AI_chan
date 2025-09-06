import 'dart:async';
import 'dart:typed_data';

/// Simple energy-based VAD (Voice Activity Detector).
/// - Feed PCM16LE mono chunks via [feed].
/// - Emits onSpeechStart/onSpeechEnd callbacks.
class VadService {
  VadService({
    this.onSpeechStart,
    this.onSpeechEnd,
    this.thresholdRms = 0.02,
    this.silenceMs = 220,
  });
  final void Function()? onSpeechStart;
  final void Function()? onSpeechEnd;
  final double thresholdRms; // e.g. 0.02
  final int silenceMs; // ms to consider end of speech

  bool _inSpeech = false;
  Timer? _endTimer;

  /// Feed raw PCM16LE bytes (mono). Computes RMS over the chunk and updates state.
  void feed(final Uint8List pcm16Bytes) {
    if (pcm16Bytes.isEmpty) return;
    final len = pcm16Bytes.length & ~1;
    if (len == 0) return;

    double sum = 0.0;
    int count = 0;
    for (int i = 0; i < len; i += 2) {
      int s = pcm16Bytes[i] | (pcm16Bytes[i + 1] << 8);
      if (s & 0x8000 != 0) s = s - 0x10000;
      final double f = s / 32768.0;
      sum += f.abs();
      count++;
    }
    if (count == 0) return;
    final rms = sum / count; // approximate average absolute value

    if (rms >= thresholdRms) {
      // Detected activity
      if (!_inSpeech) {
        _inSpeech = true;
        try {
          onSpeechStart?.call();
        } catch (_) {}
      }
      // reset end timer
      _endTimer?.cancel();
      _endTimer = Timer(Duration(milliseconds: silenceMs), () {
        // timer triggers speech end if not reset
        _inSpeech = false;
        try {
          onSpeechEnd?.call();
        } catch (_) {}
      });
    } else {
      // low energy: if in speech, ensure we schedule end sooner
      if (_inSpeech) {
        _endTimer?.cancel();
        _endTimer = Timer(Duration(milliseconds: silenceMs), () {
          _inSpeech = false;
          try {
            onSpeechEnd?.call();
          } catch (_) {}
        });
      }
    }
  }

  void dispose() {
    _endTimer?.cancel();
    _endTimer = null;
  }
}
