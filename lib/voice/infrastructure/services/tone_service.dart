import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import '../../domain/interfaces/i_tone_service.dart';

/// 🎯 DDD: Tone service implementation with all recovered cyberpunk effects
class ToneService implements IToneService {
  // Will be injected through DI

  ToneService.withPlayer(this._player);
  ToneService._() : _player = null;
  static final ToneService instance = ToneService._();

  final dynamic _player;

  @override
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

      if (_player != null) {
        try {
          await _player!.stop();
        } on Exception catch (_) {}
        await _player!.play(wav);
      }
    } on Exception catch (_) {}
  }

  /// 🎵 Generate hangup/error tone WAV based on preset
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
      case 'sweep':
        return _buildSweepWav(sampleRate: sampleRate, durationMs: durationMs);
      case 'messenger':
        return _buildDoubleBeepWav(sampleRate: sampleRate);
      case 'melodic':
      default:
        return _buildMelodicHangupWav(sampleRate: sampleRate);
    }
  }

  // 🌊 Preset: sweep descendente (700->400Hz)
  static Uint8List _buildSweepWav({
    final int sampleRate = 24000,
    final int durationMs = 350,
    final double startHz = 700,
    final double endHz = 400,
    final double volume = 0.35,
  }) {
    final totalSamples = (sampleRate * durationMs / 1000).round();
    final int16 = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final f = startHz + (endHz - startHz) * (i / totalSamples);
      final env = _adsrEnvelope(i, totalSamples, sampleRate);
      final s = math.sin(2 * math.pi * f * t);
      final amp = (32767 * volume * env).round();
      int16[i] = (amp * s).round();
    }

    final pcm = Uint8List.view(int16.buffer);
    return _pcm16ToWav(pcm, sampleRate: sampleRate);
  }

  // 📱 Preset: doble beep estilo mensajería
  static Uint8List _buildDoubleBeepWav({
    final int sampleRate = 24000,
    final double volume = 0.38,
  }) {
    const b1Ms = 120;
    const pauseMs = 70;
    const b2Ms = 160;

    final beepStructure = _createDoubleBeepStructure(
      sampleRate: sampleRate,
      b1Ms: b1Ms,
      pauseMs: pauseMs,
      b2Ms: b2Ms,
    );
    final int16 = beepStructure.int16;

    // Beep 1
    _fillBeepBasic(
      int16,
      0,
      beepStructure.b1Samples,
      660.0,
      600.0,
      sampleRate,
      volume,
    );

    // Silencio
    _applySilenceBetweenBeeps(
      int16,
      beepStructure.b1Samples,
      beepStructure.gapSamples,
    );

    // Beep 2
    _fillBeepBasic(
      int16,
      beepStructure.b1Samples + beepStructure.gapSamples,
      beepStructure.b2Samples,
      540.0,
      500.0,
      sampleRate,
      volume,
    );

    final pcm = Uint8List.view(int16.buffer);
    return _pcm16ToWav(pcm, sampleRate: sampleRate);
  }

  // 🤖 Preset: cyberpunk metálico con ring-mod
  static Uint8List _buildCyberpunkHangupWav({
    final int sampleRate = 24000,
    final int durationMs = 360,
  }) {
    const b1Ms = 90;
    const pauseMs = 60;
    const b2Ms = 120;

    final beepStructure = _createDoubleBeepStructure(
      sampleRate: sampleRate,
      b1Ms: b1Ms,
      pauseMs: pauseMs,
      b2Ms: b2Ms,
    );
    final int16 = beepStructure.int16;

    _fillBeepCyberpunk(
      int16,
      0,
      beepStructure.b1Samples,
      1900.0,
      1600.0,
      sampleRate,
    );

    _applySilenceBetweenBeeps(
      int16,
      beepStructure.b1Samples,
      beepStructure.gapSamples,
    );

    _fillBeepCyberpunk(
      int16,
      beepStructure.b1Samples + beepStructure.gapSamples,
      beepStructure.b2Samples,
      1300.0,
      1100.0,
      sampleRate,
    );

    final pcm = Uint8List.view(int16.buffer);
    return _pcm16ToWav(pcm, sampleRate: sampleRate);
  }

  // 🎼 Preset: melódico limpio coherente con ringback
  static Uint8List _buildMelodicHangupWav({final int sampleRate = 44100}) {
    const int b1Ms = 120;
    const int gapMs = 70;
    const int b2Ms = 160;

    final int b1 = (sampleRate * b1Ms / 1000).round();
    final int gap = (sampleRate * gapMs / 1000).round();
    final int b2 = (sampleRate * b2Ms / 1000).round();
    final int N = b1 + gap + b2;
    final Float64List buf = Float64List(N);

    double midiHz(final int m) => 440.0 * math.pow(2.0, (m - 69) / 12.0);

    final int glideSamples = (0.018 * sampleRate).round();
    final int sparkleSamples = (0.040 * sampleRate).round();
    final int noiseSamples = (0.012 * sampleRate).round();

    void fillBeep({
      required final int startIndex,
      required final int samples,
      required final int midi,
      final double bendSemis = -0.18,
    }) {
      final rng = math.Random(9000 + midi + startIndex);
      final double f0 = midiHz(midi);

      for (int i = 0; i < samples; i++) {
        final t = i / sampleRate;
        final globalIdx = startIndex + i;
        final env = _adsrEnvelope(i, samples, sampleRate);

        // Bend de frecuencia
        final bendRatio = math.pow(2.0, bendSemis * (i / samples) / 12.0);
        final f = f0 * bendRatio;

        // Tono base
        double s = math.sin(2 * math.pi * f * t) * env;

        // Micro glide en ataque
        if (i < glideSamples) {
          final glideF = f0 * 1.05;
          final glideMix = 1.0 - (i / glideSamples);
          s += 0.3 * math.sin(2 * math.pi * glideF * t) * env * glideMix;
        }

        // Sparkle brillante
        if (i < sparkleSamples) {
          final sparkleF = f * 3.0;
          final sparkleMix = 0.08 * (1.0 - (i / sparkleSamples));
          s += sparkleMix * math.sin(2 * math.pi * sparkleF * t) * env;
        }

        // Ruido muy sutil
        if (i < noiseSamples) {
          final noiseMix = 0.012 * (1.0 - (i / noiseSamples));
          s += noiseMix * (rng.nextDouble() * 2.0 - 1.0) * env;
        }

        buf[globalIdx] += s * 0.7;
      }
    }

    // D#5 seguido de C#5 para cerrar (coherente con motivo en D# menor)
    fillBeep(startIndex: 0, samples: b1, midi: 75, bendSemis: -0.10);
    fillBeep(startIndex: b1 + gap, samples: b2, midi: 73, bendSemis: -0.22);

    // Eco sutil único
    final int de = (0.070 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      if (i - de >= 0) buf[i] += 0.07 * buf[i - de];
    }

    // Filtros: HPF 120 Hz + LPF 6.5 kHz
    _applyHighLowPassFilters(buf, sampleRate);

    // Normalización con headroom generoso
    double peak = 0.0;
    for (int i = 0; i < N; i++) {
      final v = buf[i].abs();
      if (v > peak) peak = v;
    }
    final double norm = peak > 0 ? 0.44 / peak : 1.0;
    final Int16List pcm = Int16List(N);
    for (int i = 0; i < N; i++) {
      pcm[i] = (buf[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
    }
    return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
  }

  @override
  Future<List<int>> generateRingbackTone({
    final int sampleRate = 44100,
    final double durationSeconds = 2.5,
    final double tempoBpm = 130.0,
    final String preset = 'cyberpunk',
  }) async {
    switch (preset) {
      case 'cyberpunk':
        return buildCyberRingtoneWav(
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
          tempo: tempoBpm,
        );
      case 'melodic':
      default:
        return buildMelodicRingbackWav(
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
        );
    }
  }

  @override
  Future<List<int>> generateRingtone({
    final int sampleRate = 44100,
    final double durationSeconds = 2.5,
    final String preset = 'melodic',
    final bool stereo = true,
  }) async {
    switch (preset) {
      case 'cyberpunk':
        return buildCyberRingtoneWav(
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
        );
      case 'pad':
        return buildMelodicPadRingtoneWav(
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
          stereo: stereo,
        );
      case 'melodic':
      default:
        return buildMelodicRingtoneWav(
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
          stereo: stereo,
        );
    }
  }

  /// 🤖 CyberRingtone: pulsos metálicos por beats
  static Uint8List buildCyberRingtoneWav({
    final double durationSeconds = 2.5,
    final int sampleRate = 44100,
    final double tempo = 130.0,
  }) {
    final int sampleCount = (durationSeconds * sampleRate).round();
    final Float64List samples = Float64List(sampleCount);

    final double beatInterval = 60.0 / tempo;
    final int samplesPerBeat = (beatInterval * sampleRate).round();

    const double baseClickFreq = 880.0;
    const double ringFreq = 1200.0;
    const double detune = 1.01;
    final math.Random rng = math.Random(12345);

    double envAtSample(final int t, final int onsetSample) {
      final int rel = t - onsetSample;
      if (rel < 0) return 0.0;

      final double attack = (0.005 * sampleRate);
      final double decay = (0.06 * sampleRate);
      final double release = (0.02 * sampleRate);

      if (rel <= attack) return rel / attack;
      if (rel <= attack + decay) {
        return 1.0 - 0.7 * ((rel - attack) / decay);
      }
      if (rel <= attack + decay + release) {
        return 0.3 * (1.0 - ((rel - attack - decay) / release));
      }
      return 0.0;
    }

    for (int t = 0; t < sampleCount; t++) {
      double s = 0.0;
      final int beatIndex = (t / samplesPerBeat).floor();

      for (int k = 0; k <= 1; k++) {
        final int onsetSample =
            beatIndex * samplesPerBeat + k * (samplesPerBeat ~/ 2);
        if (onsetSample <= t && onsetSample + (0.1 * sampleRate) > t) {
          final double env = envAtSample(t, onsetSample);
          final double clickT = (t - onsetSample) / sampleRate;

          final double f1 = baseClickFreq * (1 + 0.2 * k);
          final double f2 = f1 * detune;
          final double ringF = ringFreq + 100 * k;

          final double click1 = math.sin(2 * math.pi * f1 * clickT);
          final double click2 = math.sin(2 * math.pi * f2 * clickT);
          final double ring = math.sin(2 * math.pi * ringF * clickT);
          final double ringMod = click1 * ring * 0.3;
          final double noise = (rng.nextDouble() * 2.0 - 1.0) * 0.05;

          s += env * (0.6 * click1 + 0.4 * click2 + ringMod + noise);
        }
      }
      samples[t] = s;
    }

    // Normalizar
    double peak = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final double v = samples[i].abs();
      if (v > peak) peak = v;
    }
    final double norm = peak > 0 ? 0.9 / peak : 1.0;

    final Int16List pcm = Int16List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final int val = (samples[i] * norm * 32767.0).toInt();
      pcm[i] = val;
    }
    return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
  }

  /// 🎼 Melodic ringtone: motivo en D# menor con espacial
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
        440.0 * math.pow(2.0, (midi - 69) / 12.0);

    final notes = <Map<String, num>>[
      {'m': 75, 'start': 0.00, 'dur': 0.28},
      {'m': 73, 'start': 0.33, 'dur': 0.22},
      {'m': 70, 'start': 0.58, 'dur': 0.22},
      {'m': 66, 'start': 0.83, 'dur': 0.20},
      {'m': 68, 'start': 1.07, 'dur': 0.28},
      {'m': 75, 'start': 1.43, 'dur': 0.34},
      {'m': 73, 'start': 1.86, 'dur': 0.22},
      {'m': 68, 'start': 2.11, 'dur': 0.30},
    ];

    double env(final double x, final double noteDur) {
      const a = 0.004;
      const d = 0.080;
      const r = 0.040;
      if (x < 0) return 0.0;
      if (x <= a) return x / a;
      if (x <= a + d) return 1.0 - 0.6 * ((x - a) / d);
      final sustainEnd = noteDur - r;
      if (x <= sustainEnd) return 0.4;
      if (x <= noteDur) return 0.4 * (1.0 - ((x - sustainEnd) / r));
      return 0.0;
    }

    for (final n in notes) {
      final int midi = n['m']!.toInt();
      final double start = (n['start']!).toDouble();
      final double dur = (n['dur']!).toDouble();
      final int onset = (start * sampleRate).round();
      final int nsamp = (dur * sampleRate).round();
      final double f0 = freqFromMidi(midi);
      final double bendSemis = (dur >= 0.30) ? 0.12 : 0.0;

      for (int i = 0; i < nsamp; i++) {
        final t = (onset + i) / sampleRate;
        final relT = i / sampleRate;
        final e = env(relT, dur);
        final bendRatio = math.pow(2.0, bendSemis * (i / nsamp) / 12.0);
        final f = f0 * bendRatio;

        final s1 = math.sin(2 * math.pi * f * t);
        final s2 = math.sin(2 * math.pi * f * 1.003 * t);
        final h2 = math.sin(2 * math.pi * f * 2.0 * t) * 0.15;
        final ringMod = s1 * math.sin(2 * math.pi * f * 3.1 * t) * 0.05;

        final idx = onset + i;
        if (idx < sampleCount) {
          dry[idx] += e * (0.5 * s1 + 0.3 * s2 + h2 + ringMod);
        }
      }
    }

    // Early reflections
    final int d1 = (echo1Ms * 0.001 * sampleRate).round();
    final int d2 = (echo2Ms * 0.001 * sampleRate).round();
    for (int i = sampleCount - 1; i >= 0; i--) {
      double v = dry[i];
      if (i - d1 >= 0) v += echoGain1 * dry[i - d1];
      if (i - d2 >= 0) v += echoGain2 * dry[i - d2];
      dry[i] = v;
    }

    // Filtro paso bajo
    final double fcLp = 7000.0;
    final double alphaLp =
        (2 * math.pi * fcLp) / (2 * math.pi * fcLp + sampleRate);
    double y = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      y += alphaLp * (dry[i] - y);
      dry[i] = y;
    }

    if (!stereo) {
      double peak = 0.0;
      for (int i = 0; i < sampleCount; i++) {
        final v = dry[i].abs();
        if (v > peak) peak = v;
      }
      final double norm = peak > 0 ? 0.89 / peak : 1.0;
      final Int16List pcm = Int16List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        pcm[i] = (dry[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      }
      return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
    }

    // Estéreo processing...
    final List<double> left = List<double>.from(dry, growable: false);
    final List<double> right = List<double>.from(dry, growable: false);

    final int haas = (haasMs * 0.001 * sampleRate).round().clamp(
      0,
      sampleCount,
    );
    for (int i = sampleCount - 1; i >= 0; i--) {
      double r = right[i];
      if (i - haas >= 0) r += width * dry[i - haas];
      right[i] = r;
    }

    // Pan LFO
    if (panDepth > 0.0 && panLfoHz > 0.0) {
      for (int i = 0; i < sampleCount; i++) {
        final t = i / sampleRate;
        final panOffset = panDepth * math.sin(2 * math.pi * panLfoHz * t);
        final leftGain = 0.5 + panOffset;
        final rightGain = 0.5 - panOffset;
        left[i] *= leftGain;
        right[i] *= rightGain;
      }
    }

    // Normalización estéreo
    double peak = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final al = left[i].abs();
      final ar = right[i].abs();
      if (al > peak) peak = al;
      if (ar > peak) peak = ar;
    }
    final double norm = peak > 0 ? 0.88 / peak : 1.0;
    final Int16List pcm = Int16List(sampleCount * 2);
    int w = 0;
    for (int i = 0; i < sampleCount; i++) {
      final int L = (left[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      final int R = (right[i] * norm * 32767.0)
          .clamp(-32768.0, 32767.0)
          .toInt();
      pcm[w++] = L;
      pcm[w++] = R;
    }
    return _pcm16ToWav(
      Uint8List.view(pcm.buffer),
      sampleRate: sampleRate,
      channels: 2,
    );
  }

  /// 🎹 Melodic pad ringtone: sostenido espacial
  static Uint8List buildMelodicPadRingtoneWav({
    final double durationSeconds = 2.5,
    final int sampleRate = 44100,
    final bool stereo = true,
    final double detuneCents = 4.0,
    final double vibratoHz = 3.0,
    final double vibratoCents = 2.0,
    final double haasMs = 0.7,
    final double width = 0.12,
    final double echo1Ms = 140.0,
    final double echoGain1 = 0.06,
    final double lpfStartHz = 6600.0,
    final double lpfEndHz = 6600.0,
  }) {
    final int N = (durationSeconds * sampleRate).round();
    final Float64List dry = Float64List(N);

    double midiHz(final int m) => 440.0 * math.pow(2.0, (m - 69) / 12.0);
    double centsToRatio(final double cents) =>
        math.pow(2.0, cents / 1200.0).toDouble();

    final tones = <int>[75, 78, 70]; // D#m triad
    final double dtn = centsToRatio(detuneCents);
    final double dtp = centsToRatio(-detuneCents);

    double envGlobal(final double t) {
      const at = 0.030;
      const rt = 0.080;
      if (t < at) return t / at;
      if (t > durationSeconds - rt) return (durationSeconds - t) / rt;
      return 1.0;
    }

    for (int i = 0; i < N; i++) {
      final double t = i / sampleRate;
      final double vib = centsToRatio(
        vibratoCents * math.sin(2 * math.pi * vibratoHz * t),
      );
      double acc = 0.0;

      for (final m in tones) {
        final f = midiHz(m) * vib;
        acc += math.sin(2 * math.pi * f * t);
        acc += math.sin(2 * math.pi * f * dtn * t) * 0.7;
        acc += math.sin(2 * math.pi * f * dtp * t) * 0.7;
      }
      dry[i] = acc * 0.5 * envGlobal(t);
    }

    // HPF para evitar acumulación de bajas
    _applyHighLowPassFilters(dry, sampleRate, lowPassHz: 0);

    // Reflexión temprana
    final int d1 = (echo1Ms * 0.001 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      double v = dry[i];
      if (i - d1 >= 0) v += echoGain1 * dry[i - d1];
      dry[i] = v;
    }

    // LPF dinámico
    final List<double> lpfOut = List<double>.filled(N, 0.0);
    double yLpf = 0.0;
    for (int i = 0; i < N; i++) {
      final double tt = i / (N - 1).clamp(1, N);
      final double fc = (lpfStartHz == lpfEndHz)
          ? lpfStartHz
          : (lpfStartHz + (lpfEndHz - lpfStartHz) * tt);
      final double alpha = (2 * math.pi * fc) / (2 * math.pi * fc + sampleRate);
      yLpf += alpha * (dry[i] - yLpf);
      lpfOut[i] = yLpf;
    }

    if (!stereo) {
      double peak = 0.0;
      for (int i = 0; i < N; i++) {
        final v = lpfOut[i].abs();
        if (v > peak) peak = v;
      }
      final double norm = peak > 0 ? 0.86 / peak : 1.0;
      final Int16List pcm = Int16List(N);
      for (int i = 0; i < N; i++) {
        pcm[i] = (lpfOut[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      }
      return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
    }

    // Estéreo Haas
    final List<double> L = List<double>.from(lpfOut, growable: false);
    final List<double> R = List<double>.from(lpfOut, growable: false);
    final int haas = (haasMs * 0.001 * sampleRate).round().clamp(0, N);

    for (int i = N - 1; i >= 0; i--) {
      if (i - haas >= 0) R[i] += width * lpfOut[i - haas];
    }

    for (int i = 0; i < N; i++) {
      L[i] *= (1.0 + width * 0.5);
      R[i] *= (1.0 - width * 0.5);
    }

    double peak = 0.0;
    for (int i = 0; i < N; i++) {
      final a = L[i].abs();
      final b = R[i].abs();
      if (a > peak) peak = a;
      if (b > peak) peak = b;
    }
    final double norm = peak > 0 ? 0.72 / peak : 1.0;
    final Int16List pcm = Int16List(N * 2);
    int w = 0;
    for (int i = 0; i < N; i++) {
      final int l = (L[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      final int r = (R[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      pcm[w++] = l;
      pcm[w++] = r;
    }
    return _pcm16ToWav(
      Uint8List.view(pcm.buffer),
      sampleRate: sampleRate,
      channels: 2,
    );
  }

  /// 🎵 Melodic ringback: motivo + silencio para tono de llamada
  static Uint8List buildMelodicRingbackWav({
    final double durationSeconds = 2.5,
    final int sampleRate = 44100,
  }) {
    final int N = (durationSeconds * sampleRate).round();
    final Float64List buf = Float64List(N);

    double midiHz(final int m) => 440.0 * math.pow(2.0, (m - 69) / 12.0);

    final notes = <Map<String, num>>[
      {'m': 75, 'start': 0.00, 'dur': 0.48, 'vel': 1.0},
      {'m': 80, 'start': 0.40, 'dur': 0.36, 'vel': 0.95},
      {'m': 78, 'start': 0.78, 'dur': 0.55, 'vel': 0.92},
    ];

    double env(final double x, final double dur) {
      const a = 0.007;
      const d = 0.090;
      const r = 0.060;
      if (x < 0) return 0.0;
      if (x <= a) return x / a;
      if (x <= a + d) return 1.0 - 0.75 * ((x - a) / d);
      if (x <= dur - r) return 0.25;
      if (x <= dur) return 0.25 * (1.0 - (x - (dur - r)) / r);
      return 0.0;
    }

    for (final n in notes) {
      final int midi = n['m']!.toInt();
      final double start = (n['start']!).toDouble();
      final double dur = (n['dur']!).toDouble();
      final double vel = (n['vel']!).toDouble();
      final int onset = (start * sampleRate).round();
      final int ns = (dur * sampleRate).round();
      final double f = midiHz(midi);

      final int glideSamples = (0.020 * sampleRate).round();
      final int sparkleSamples = (0.040 * sampleRate).round();
      final int noiseSamples = (0.012 * sampleRate).round();
      final rng = math.Random(1337 + midi);

      for (int i = 0; i < ns; i++) {
        final t = (onset + i) / sampleRate;
        final relT = i / sampleRate;
        final e = env(relT, dur) * vel;
        final idx = onset + i;
        if (idx >= N) break;

        double s = math.sin(2 * math.pi * f * t);

        if (i < glideSamples) {
          final glideF = f * 1.03;
          final glideMix = 0.2 * (1.0 - (i / glideSamples));
          s += glideMix * math.sin(2 * math.pi * glideF * t);
        }

        if (i < sparkleSamples) {
          final sparkleF = f * 2.8;
          final sparkleMix = 0.06 * (1.0 - (i / sparkleSamples));
          s += sparkleMix * math.sin(2 * math.pi * sparkleF * t);
        }

        if (i < noiseSamples) {
          final noiseMix = 0.008 * (1.0 - (i / noiseSamples));
          s += noiseMix * (rng.nextDouble() * 2.0 - 1.0);
        }

        buf[idx] += s * e;
      }
    }

    // Eco sutil
    final int de = (0.090 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      if (i - de >= 0) buf[i] += 0.090 * buf[i - de];
    }

    // Filtros
    _applyHighLowPassFilters(buf, sampleRate);

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

  @override
  Future<void> playCustomTone({
    required final double frequency,
    required final int durationMs,
    final double volume = 1.0,
  }) async {
    await playHangupOrErrorTone(durationMs: durationMs, preset: 'sweep');
  }

  @override
  Future<void> playFrequencySweep({
    required final double startFreq,
    required final double endFreq,
    required final int durationMs,
    final double volume = 1.0,
  }) async {
    await playHangupOrErrorTone(durationMs: durationMs, preset: 'sweep');
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } on Exception catch (_) {}
  }

  @override
  Future<bool> isAvailable() async {
    return _player != null;
  }

  // 🔧 Helper functions

  static double _adsrEnvelope(
    final int i,
    final int totalSamples,
    final int sampleRate, {
    final int attackMs = 5,
    final int releaseMs = 30,
    final double sustain = 1.0,
  }) {
    final a = (sampleRate * attackMs / 1000).clamp(1, totalSamples).toInt();
    final r = (sampleRate * releaseMs / 1000).clamp(1, totalSamples).toInt();

    if (i < a) return i / a;

    final relStart = totalSamples - r;
    if (i >= relStart) {
      final x = (i - relStart) / r;
      return (1.0 - x) * sustain;
    }
    return sustain;
  }

  static void _applySilenceBetweenBeeps(
    final Int16List int16,
    final int b1Samples,
    final int gapSamples,
  ) {
    for (int i = 0; i < gapSamples; i++) {
      int16[b1Samples + i] = 0;
    }
  }

  static void _fillBeepCyberpunk(
    final Int16List int16,
    final int startIndex,
    final int samples,
    final double fStart,
    final double fEnd,
    final int sampleRate,
  ) {
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final f = fStart + (fEnd - fStart) * (i / samples);
      final env = _adsrEnvelope(i, samples, sampleRate);

      // Base sine + ring modulation + bitcrush effect
      final s1 = math.sin(2 * math.pi * f * t);
      final s2 = math.sin(2 * math.pi * f * 1.7 * t);
      final ringMod = s1 * s2 * 0.4;
      final mixed = s1 * 0.6 + ringMod;

      // Light bitcrush
      final crushSteps = 128;
      final crushed = (mixed * crushSteps).round() / crushSteps;

      final amp = (32767 * 0.5 * env).round();
      int16[startIndex + i] = (amp * crushed).round();
    }
  }

  static void _fillBeepBasic(
    final Int16List int16,
    final int startIndex,
    final int samples,
    final double fStart,
    final double fEnd,
    final int sampleRate,
    final double volume,
  ) {
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final f = fStart + (fEnd - fStart) * (i / samples);
      final env = _adsrEnvelope(i, samples, sampleRate);
      final s = math.sin(2 * math.pi * f * t);
      final amp = (32767 * volume * env).round();
      int16[startIndex + i] = (amp * s).round();
    }
  }

  static ({
    int b1Samples,
    int gapSamples,
    int b2Samples,
    int total,
    Int16List int16,
  })
  _createDoubleBeepStructure({
    required final int sampleRate,
    required final int b1Ms,
    required final int pauseMs,
    required final int b2Ms,
  }) {
    final b1Samples = (sampleRate * b1Ms / 1000).round();
    final gapSamples = (sampleRate * pauseMs / 1000).round();
    final b2Samples = (sampleRate * b2Ms / 1000).round();
    final total = b1Samples + gapSamples + b2Samples;
    final int16 = Int16List(total);

    return (
      b1Samples: b1Samples,
      gapSamples: gapSamples,
      b2Samples: b2Samples,
      total: total,
      int16: int16,
    );
  }

  static void _applyHighLowPassFilters(
    final List<double> buffer,
    final int sampleRate, {
    final double highPassHz = 120.0,
    final double lowPassHz = 6500.0,
  }) {
    final N = buffer.length;

    // High-pass filter
    if (highPassHz > 0 && highPassHz.isFinite) {
      final double fc = highPassHz;
      final double alpha = (2 * math.pi * fc) / (2 * math.pi * fc + sampleRate);
      double x1 = 0.0, y1 = 0.0;

      for (int i = 0; i < N; i++) {
        final x0 = buffer[i];
        final y0 = alpha * (y1 + x0 - x1);
        buffer[i] = y0;
        x1 = x0;
        y1 = y0;
      }
    }

    // Low-pass filter
    if (lowPassHz > 0 && lowPassHz.isFinite) {
      final double fc = lowPassHz;
      final double alpha = (2 * math.pi * fc) / (2 * math.pi * fc + sampleRate);
      double y = 0.0;

      for (int i = 0; i < N; i++) {
        y += alpha * (buffer[i] - y);
        buffer[i] = y;
      }
    }
  }

  static Uint8List _pcm16ToWav(
    final Uint8List pcm, {
    required final int sampleRate,
    final int channels = 1,
  }) {
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final dataSize = pcm.lengthInBytes;
    final chunkSize = 36 + dataSize;

    final header = BytesBuilder();
    header.add(ascii.encode('RIFF'));
    header.add(_le32(chunkSize));
    header.add(ascii.encode('WAVE'));
    header.add(ascii.encode('fmt '));
    header.add(_le32(16));
    header.add(_le16(1));
    header.add(_le16(channels));
    header.add(_le32(sampleRate));
    header.add(_le32(byteRate));
    header.add(_le16(blockAlign));
    header.add(_le16(16));
    header.add(ascii.encode('data'));
    header.add(_le32(dataSize));

    final out = BytesBuilder();
    out.add(header.takeBytes());
    out.add(pcm);
    return out.takeBytes();
  }

  static Uint8List _le16(final int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

  static Uint8List _le32(final int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
}
