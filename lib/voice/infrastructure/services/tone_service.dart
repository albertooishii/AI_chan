import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ai_chan/core/di.dart' as di;
import '../../domain/interfaces/i_tone_service.dart';

/// Servicio de efectos sonoros compartidos (tono único para colgado y error de conexión)
class ToneService implements IToneService {
  ToneService._();
  static final ToneService instance = ToneService._();

  final _player = di.getAudioPlayback();

  /// Reproduce el tono único sin bloquear la UI.
  /// preset:
  ///  - 'messenger' (default): doble beep corto (640Hz ~120ms + 520Hz ~160ms con micro pausa)
  ///  - 'sweep': beep descendente (700->400Hz) ~350ms
  ///  - 'cyberpunk': beeps metálicos con ligero bitcrush/ring-mod, estética futurista
  Future<void> playHangupOrErrorTone({
    final int sampleRate = 24000,
    final int durationMs = 350,
    final String preset = 'melodic',
  }) async {
    try {
      final wav = buildHangupOrErrorToneWav(
        sampleRate: sampleRate,
        durationMs: durationMs,
        preset: preset,
      );
      try {
        await _player.stop();
      } on Exception catch (_) {}
      await _player.play(wav);
      // No esperamos a que termine: el llamador decide si bloquear o no
    } on Exception catch (_) {}
  }

  /// 📞 Play ringtone/RBT (Ring Back Tone) - Implementación de IToneService
  @override
  Future<void> playRingtone({
    final int durationMs = 3000,
    final bool cyberpunkStyle = true,
  }) async {
    try {
      final wav = cyberpunkStyle
          ? buildMelodicRingtoneWav(durationSeconds: durationMs / 1000.0)
          : buildMelodicRingbackWav(durationSeconds: durationMs / 1000.0);
      try {
        await _player.stop();
      } on Exception catch (_) {}
      await _player.play(wav);
    } on Exception catch (_) {}
  }

  /// 📵 Play hangup/error tone - Implementación de IToneService
  @override
  Future<void> playHangupTone({
    final int durationMs = 350,
    final bool cyberpunkStyle = true,
  }) async {
    final preset = cyberpunkStyle ? 'cyberpunk' : 'melodic';
    await playHangupOrErrorTone(durationMs: durationMs, preset: preset);
  }

  /// Stop any current playback - Implementación de IToneService
  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } on Exception catch (_) {}
  }

  /// Check if service is available - Implementación de IToneService
  @override
  Future<bool> isAvailable() async {
    try {
      return true; // El servicio siempre está disponible
    } on Exception catch (_) {
      return false;
    }
  }

  /// Genera el WAV PCM16 mono del tono de colgado/errores según preset
  static Uint8List buildHangupOrErrorToneWav({
    final int sampleRate = 24000,
    final int durationMs = 350,
    final String preset = 'melodic',
  }) {
    switch (preset) {
      case 'cyberpunk':
        return _buildCyberpunkHangupWav(
          sampleRate: sampleRate,
          durationMs: durationMs,
        );
      case 'melodic':
      default:
        return _buildMelodicHangupWav(sampleRate: sampleRate);
    }
  }

  static Uint8List _buildCyberpunkHangupWav({
    final int sampleRate = 24000,
    final int durationMs = 360,
  }) {
    final totalSamples = (sampleRate * durationMs / 1000).round();
    final int16 = Int16List(totalSamples);
    final rng = math.Random(42);

    // Cyberpunk hangup: beep doble metálico con efectos
    final f1 = 450.0, f2 = 320.0;
    final beep1Duration = 0.12, beep2Duration = 0.16, pauseDuration = 0.04;
    final s1 = (sampleRate * beep1Duration).round();
    final p = (sampleRate * pauseDuration).round();
    final s2 = (sampleRate * beep2Duration).round();

    // Beep 1
    for (int i = 0; i < s1 && i < totalSamples; i++) {
      final t = i / sampleRate;
      final env = math.sin(math.pi * i / s1);
      var s = math.sin(2 * math.pi * f1 * t);
      // Ring modulation sutil
      s *= (1.0 + 0.3 * math.sin(2 * math.pi * 23.0 * t));
      // Bitcrush ligero
      s = (s * 32.0).floor() / 32.0;
      // Ruido digital
      s += 0.08 * ((rng.nextDouble() * 2.0) - 1.0);
      int16[i] = (s * env * 16000.0).clamp(-32768.0, 32767.0).toInt();
    }

    // Pausa
    for (int i = s1; i < s1 + p && i < totalSamples; i++) {
      int16[i] = 0;
    }

    // Beep 2
    for (int i = s1 + p; i < s1 + p + s2 && i < totalSamples; i++) {
      final t = (i - s1 - p) / sampleRate;
      final env = math.sin(math.pi * (i - s1 - p) / s2);
      var s = math.sin(2 * math.pi * f2 * t);
      s *= (1.0 + 0.3 * math.sin(2 * math.pi * 17.0 * t));
      s = (s * 32.0).floor() / 32.0;
      s += 0.08 * ((rng.nextDouble() * 2.0) - 1.0);
      int16[i] = (s * env * 14000.0).clamp(-32768.0, 32767.0).toInt();
    }

    return _pcm16ToWav(Uint8List.view(int16.buffer), sampleRate: sampleRate);
  }

  static Uint8List _buildMelodicHangupWav({final int sampleRate = 44100}) {
    // Tono melódico descendente D#5 -> A#4 con reverb
    final durationSec = 0.8;
    final totalSamples = (sampleRate * durationSec).round();
    final buf = Float64List(totalSamples);

    // D#5 = 622.25 Hz, A#4 = 466.16 Hz
    final f1 = 622.25, f2 = 466.16;

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final progress = t / durationSec;
      final freq = f1 + (f2 - f1) * progress;
      final env = math.exp(-3.0 * t); // Decay exponencial

      var s = math.sin(2 * math.pi * freq * t);
      s += 0.3 * math.sin(2 * math.pi * freq * 2.0 * t); // Armónico
      buf[i] = s * env * 0.4;
    }

    // Reverb simple
    final delay = (0.08 * sampleRate).round();
    for (int i = totalSamples - 1; i >= 0; i--) {
      if (i - delay >= 0) {
        buf[i] += 0.25 * buf[i - delay];
      }
    }

    // Convertir a PCM16
    final pcm = Int16List(totalSamples);
    for (int i = 0; i < totalSamples; i++) {
      pcm[i] = (buf[i] * 32767.0).clamp(-32768.0, 32767.0).toInt();
    }

    return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
  }

  /// Tono de llamada melódico cyberpunk - ¡EL QUE SUENA BIEN!
  static Uint8List buildMelodicRingtoneWav({
    final double durationSeconds = 2.5,
    final int sampleRate = 44100,
    final bool stereo = true,
    final double haasMs = 1.8,
    final double width = 0.22,
    final double echo1Ms = 90.0,
    final double echo2Ms = 160.0,
    final double echoGain1 = 0.18,
    final double echoGain2 = 0.12,
    final double panLfoHz = 0.18,
    final double panDepth = 0.06,
  }) {
    final int sampleCount = (durationSeconds * sampleRate).round();
    final Float64List dry = Float64List(sampleCount);

    double freqFromMidi(final int midi) =>
        440.0 * math.pow(2.0, (midi - 69) / 12.0).toDouble();

    // Motivo en D# menor (D# natural minor), 2.5s total
    // Tiempos aproximados (s): 0.00, 0.33, 0.58, 0.83, 1.07, 1.43, 1.86, 2.11
    // Notas MIDI (octava relativa): D#5=75, C#5=73, A#4=70, F#4=66, G#4=68
    final notes = <Map<String, num>>[
      {'m': 75, 'start': 0.00, 'dur': 0.28},
      {'m': 73, 'start': 0.33, 'dur': 0.22},
      {'m': 70, 'start': 0.58, 'dur': 0.22},
      {'m': 66, 'start': 0.83, 'dur': 0.20},
      {'m': 68, 'start': 1.07, 'dur': 0.28},
      {'m': 75, 'start': 1.43, 'dur': 0.34}, // acento
      {'m': 73, 'start': 1.86, 'dur': 0.22},
      {'m': 68, 'start': 2.11, 'dur': 0.30},
    ];

    double env(final double x, final double noteDur) {
      // ADSR: A=8ms, D=80ms a S=0.35, R=40ms
      const a = 0.008;
      const d = 0.080;
      const r = 0.040;
      if (x < 0) return 0.0;
      if (x <= a) return x / a;
      if (x <= a + d) {
        final t = (x - a) / d;
        return 1.0 - 0.65 * t; // hasta 0.35
      }
      if (x <= noteDur - r) return 0.35;
      if (x <= noteDur) return 0.35 * (1.0 - (x - (noteDur - r)) / r);
      return 0.0;
    }

    // Síntesis de notas individuales
    for (final note in notes) {
      final int midi = note['m']!.toInt();
      final double start = (note['start']!).toDouble();
      final double dur = (note['dur']!).toDouble();
      final int onset = (start * sampleRate).round();
      final int ns = (dur * sampleRate).round();
      final double f = freqFromMidi(midi);
      final rng = math.Random(1337 + midi);

      for (int i = 0; i < ns; i++) {
        final int t = onset + i;
        if (t < 0 || t >= sampleCount) continue;
        final double x = i / sampleRate;
        final double a = env(x, dur);
        if (a <= 0.0) continue;

        // Micro-glide de +18 cents -> 0 en ~28ms
        final int glideSamples = (0.028 * sampleRate).round();
        final double cents = (i < glideSamples)
            ? (18.0 * (1.0 - (i / glideSamples)))
            : 0.0;
        final double fEff = f * math.pow(2.0, cents / 1200.0);
        final double ph = 2 * math.pi * fEff * (t / sampleRate);
        var s = math.sin(ph);

        // Sparkle de octava en el ataque
        final int sparkleSamples = (0.050 * sampleRate).round();
        if (i < sparkleSamples) {
          final double es = 1.0 - (i / sparkleSamples);
          s +=
              0.12 *
              es *
              math.sin(2 * math.pi * (2.0 * fEff) * (t / sampleRate));
        }

        // Transiente de ruido en el primer instante
        final int noiseSamples = (0.015 * sampleRate).round();
        if (i < noiseSamples) {
          final double en = 1.0 - (i / noiseSamples);
          s += 0.04 * en * ((rng.nextDouble() * 2.0) - 1.0);
        }

        dry[t] += a * s;
      }
    }

    // Eco doble para espacialidad
    final int d1 = (echo1Ms * 0.001 * sampleRate).round();
    final int d2 = (echo2Ms * 0.001 * sampleRate).round();
    for (int i = sampleCount - 1; i >= 0; i--) {
      double v = dry[i];
      if (i - d1 >= 0) v += echoGain1 * dry[i - d1];
      if (i - d2 >= 0) v += echoGain2 * dry[i - d2];
      dry[i] = v;
    }

    // High-pass suave y low-pass para limpieza
    {
      final double fcHp = 140.0;
      final double aHp = sampleRate / (2 * math.pi * fcHp + sampleRate);
      double yHp = 0.0, xPrev = 0.0;
      for (int i = 0; i < sampleCount; i++) {
        final x = dry[i];
        yHp = aHp * (yHp + x - xPrev);
        xPrev = x;
        dry[i] = yHp;
      }
    }
    {
      final double fcLp = 7200.0;
      final double aLp =
          (2 * math.pi * fcLp) / (2 * math.pi * fcLp + sampleRate);
      double y = 0.0;
      for (int i = 0; i < sampleCount; i++) {
        y += aLp * (dry[i] - y);
        dry[i] = y;
      }
    }

    if (!stereo) {
      // Mono
      double peak = 0.0;
      for (int i = 0; i < sampleCount; i++) {
        final a = dry[i].abs();
        if (a > peak) peak = a;
      }
      final double norm = peak > 0 ? 0.75 / peak : 1.0;
      final Int16List pcm = Int16List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        pcm[i] = (dry[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      }
      return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
    }

    // Estéreo con Haas effect y pan LFO
    final List<double> L = List<double>.from(dry, growable: false);
    final List<double> R = List<double>.from(dry, growable: false);
    final int haas = (haasMs * 0.001 * sampleRate).round().clamp(
      0,
      sampleCount,
    );

    for (int i = sampleCount - 1; i >= 0; i--) {
      if (i - haas >= 0) {
        R[i] += width * dry[i - haas];
      }
    }

    // Pan LFO sutil
    for (int i = 0; i < sampleCount; i++) {
      final double t = i / sampleRate;
      final double lfo = panDepth * math.sin(2 * math.pi * panLfoHz * t);
      L[i] *= (1.0 + lfo);
      R[i] *= (1.0 - lfo);
    }

    // Normalización estéreo
    double peak = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final a = L[i].abs();
      final b = R[i].abs();
      if (a > peak) peak = a;
      if (b > peak) peak = b;
    }
    final double norm = peak > 0 ? 0.58 / peak : 1.0;
    final Int16List pcm = Int16List(sampleCount * 2);
    int w = 0;
    for (int i = 0; i < sampleCount; i++) {
      final int left = (L[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      final int right = (R[i] * norm * 32767.0)
          .clamp(-32768.0, 32767.0)
          .toInt();
      pcm[w++] = left;
      pcm[w++] = right;
    }
    return _pcm16ToWav(
      Uint8List.view(pcm.buffer),
      sampleRate: sampleRate,
      channels: 2,
    );
  }

  /// Ringback melódico limpio: motivo corto + silencio para sensación de tono de llamada.
  static Uint8List buildMelodicRingbackWav({
    final double durationSeconds = 2.5,
    final int sampleRate = 44100,
  }) {
    final int N = (durationSeconds * sampleRate).round();
    final Float64List buf = Float64List(N);

    double midiHz(final int m) =>
        440.0 * math.pow(2.0, (m - 69) / 12.0).toDouble();

    // Motivo en D# menor: D#5 -> G#5 -> F#5
    final notes = <Map<String, num>>[
      {'m': 75, 'start': 0.00, 'dur': 0.48, 'vel': 1.0}, // D#5
      {'m': 80, 'start': 0.40, 'dur': 0.36, 'vel': 0.95}, // G#5
      {'m': 78, 'start': 0.78, 'dur': 0.55, 'vel': 0.92}, // F#5
    ];

    double env(final double x, final double dur) {
      const a = 0.007, d = 0.090, r = 0.060;
      if (x < 0) return 0.0;
      if (x <= a) return x / a;
      if (x <= a + d) {
        final t = (x - a) / d;
        return 1.0 - 0.75 * t; // hasta 0.25
      }
      if (x <= dur - r) return 0.25;
      if (x <= dur) return 0.25 * (1.0 - (x - (dur - r)) / r);
      return 0.0;
    }

    // Síntesis del motivo
    for (final n in notes) {
      final int midi = n['m']!.toInt();
      final double start = (n['start']!).toDouble();
      final double dur = (n['dur']!).toDouble();
      final double vel = (n['vel']!).toDouble();
      final int onset = (start * sampleRate).round();
      final int ns = (dur * sampleRate).round();
      final double f = midiHz(midi);

      for (int i = 0; i < ns; i++) {
        final int t = onset + i;
        if (t < 0 || t >= N) continue;
        final double x = i / sampleRate;
        final double a = env(x, dur);
        if (a <= 0.0) continue;

        final double ph = 2 * math.pi * f * (t / sampleRate);
        final s = math.sin(ph);
        buf[t] += vel * a * s;
      }
    }

    // Eco y filtros
    final int de = (0.090 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      if (i - de >= 0) buf[i] += 0.090 * buf[i - de];
    }

    // Filtros
    {
      final double fcHp = 120.0;
      final double aHp = sampleRate / (2 * math.pi * fcHp + sampleRate);
      double yHp = 0.0, xPrev = 0.0;
      for (int i = 0; i < N; i++) {
        final x = buf[i];
        yHp = aHp * (yHp + x - xPrev);
        xPrev = x;
        buf[i] = yHp;
      }
    }
    {
      final double fcLp = 6500.0;
      final double aLp =
          (2 * math.pi * fcLp) / (2 * math.pi * fcLp + sampleRate);
      double y = 0.0;
      for (int i = 0; i < N; i++) {
        y += aLp * (buf[i] - y);
        buf[i] = y;
      }
    }

    // Fade-out para loop limpio
    final int fade = (0.030 * sampleRate).round();
    for (int i = 0; i < fade; i++) {
      final int idx = N - 1 - i;
      if (idx < 0) break;
      final double g = (i / fade);
      buf[idx] *= (1.0 - g);
    }

    // Normalizar
    double peak = 0.0;
    for (int i = 0; i < N; i++) {
      final double v = buf[i].abs();
      if (v > peak) peak = v;
    }
    final double norm = peak > 0 ? 0.44 / peak : 1.0;
    final Int16List pcm = Int16List(N);
    for (int i = 0; i < N; i++) {
      pcm[i] = (buf[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
    }
    return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
  }

  /// Convierte PCM16 a WAV
  static Uint8List _pcm16ToWav(
    final Uint8List pcm, {
    required final int sampleRate,
    final int channels = 1,
  }) {
    final int byteRate = sampleRate * channels * 2;
    final int dataSize = pcm.length;
    final int fileSize = 36 + dataSize;

    final bb = BytesBuilder();

    // WAV header
    bb.add('RIFF'.codeUnits);
    bb.add(_int32ToBytes(fileSize));
    bb.add('WAVE'.codeUnits);
    bb.add('fmt '.codeUnits);
    bb.add(_int32ToBytes(16)); // PCM header size
    bb.add(_int16ToBytes(1)); // Audio format (PCM)
    bb.add(_int16ToBytes(channels));
    bb.add(_int32ToBytes(sampleRate));
    bb.add(_int32ToBytes(byteRate));
    bb.add(_int16ToBytes(channels * 2)); // Block align
    bb.add(_int16ToBytes(16)); // Bits per sample
    bb.add('data'.codeUnits);
    bb.add(_int32ToBytes(dataSize));
    bb.add(pcm);

    return bb.toBytes();
  }

  static Uint8List _int32ToBytes(final int v) =>
      Uint8List.fromList([v, v >> 8, v >> 16, v >> 24]);
  static Uint8List _int16ToBytes(final int v) =>
      Uint8List.fromList([v, v >> 8]);
}
