import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:ai_chan/core/di.dart' as di;

/// Servicio de efectos sonoros compartidos (tono único para colgado y error de conexión)
class ToneService {
  ToneService._();
  static final ToneService instance = ToneService._();

  final _player = di.getAudioPlayback();

  /// Reproduce el tono único sin bloquear la UI.
  /// preset:
  ///  - 'messenger' (default): doble beep corto (640Hz ~120ms + 520Hz ~160ms con micro pausa)
  ///  - 'sweep': beep descendente (700->400Hz) ~350ms
  ///  - 'cyberpunk': beeps metálicos con ligero bitcrush/ring-mod, estética futurista
  Future<void> playHangupOrErrorTone({
    int sampleRate = 24000,
    int durationMs = 350,
    String preset = 'melodic',
  }) async {
    try {
      final wav = buildHangupOrErrorToneWav(
        sampleRate: sampleRate,
        durationMs: durationMs,
        preset: preset,
      );
      try {
        await _player.stop();
      } catch (_) {}
      await _player.play(wav);
      // No esperamos a que termine: el llamador decide si bloquear o no
    } catch (_) {}
  }

  /// Genera el WAV PCM16 mono del tono de colgado/errores según preset
  static Uint8List buildHangupOrErrorToneWav({
    int sampleRate = 24000,
    int durationMs = 350,
    String preset = 'melodic',
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

  // Preset: beep descendente (700->400Hz)
  static Uint8List _buildSweepWav({
    int sampleRate = 24000,
    int durationMs = 350,
    double startHz = 700,
    double endHz = 400,
    double volume = 0.35,
  }) {
    final totalSamples = (sampleRate * durationMs / 1000).round();
    final int16 = Int16List(totalSamples);
    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final f = startHz + (endHz - startHz) * (i / totalSamples);
      // Envolvente simple: ataque/decay para evitar clicks
      final env = _adsrEnvelope(
        i,
        totalSamples,
        sampleRate,
        attackMs: 6,
        releaseMs: 40,
      );
      final s = math.sin(2 * math.pi * f * t);
      final mixed = s; // seno
      final amp = (32767 * volume * env).round();
      int16[i] = (amp * mixed).round();
    }
    final pcm = Uint8List.view(int16.buffer);
    return _pcm16ToWav(pcm, sampleRate: sampleRate);
  }

  // Preset: doble beep corto estilo apps de mensajería
  static Uint8List _buildDoubleBeepWav({
    int sampleRate = 24000,
    double volume = 0.38,
  }) {
    // beep1: ~640Hz, 120ms; pausa 70ms; beep2: ~520Hz, 160ms (ligera caída de tono en cada beep)
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

    // beep1
    _fillBeepBasic(
      int16,
      0,
      beepStructure.b1Samples,
      660.0,
      600.0,
      sampleRate,
      volume,
    );
    // silencio
    _applySilenceBetweenBeeps(
      int16,
      beepStructure.b1Samples,
      beepStructure.gapSamples,
    );
    // beep2
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

  // Preset: "cyberpunk" — beeps metálicos con ring-mod, ligera distorsión y micro arpegio
  static Uint8List _buildCyberpunkHangupWav({
    int sampleRate = 24000,
    int durationMs = 360,
  }) {
    // dos beeps cortos con carácter metálico y ligera caída de tono
    // beep1 ~ 1900->1600Hz (90ms), pausa 60ms, beep2 ~ 1300->1100Hz (120ms)
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

  // Preset: Hangup melódico limpio, coherente con el ringback (seno + adornos sutiles)
  static Uint8List _buildMelodicHangupWav({int sampleRate = 44100}) {
    // Patrón: beep1 (~120ms), pausa (~70ms), beep2 (~160ms)
    const int b1Ms = 120;
    const int gapMs = 70;
    const int b2Ms = 160;
    final int b1 = (sampleRate * b1Ms / 1000).round();
    final int gap = (sampleRate * gapMs / 1000).round();
    final int b2 = (sampleRate * b2Ms / 1000).round();
    final int N = b1 + gap + b2;
    final Float64List buf = Float64List(N);

    double midiHz(int m) => 440.0 * math.pow(2.0, (m - 69) / 12.0).toDouble();

    // Misma paleta que buildMelodicRingbackWav
    final int glideSamples = (0.018 * sampleRate).round(); // ~18ms
    final int sparkleSamples = (0.040 * sampleRate).round(); // ~40ms
    final int noiseSamples = (0.012 * sampleRate).round(); // ~12ms

    void fillBeep({
      required int startIndex,
      required int samples,
      required int midi,
      double bendSemis = -0.18,
    }) {
      final rng = math.Random(9000 + midi + startIndex);
      final double f0 = midiHz(midi);
      for (int i = 0; i < samples; i++) {
        final int t = startIndex + i;
        if (t < 0 || t >= N) continue;
        // Envolvente algo más lenta/soft
        final double env = _adsrEnvelope(
          i,
          samples,
          sampleRate,
          attackMs: 6,
          releaseMs: 55,
          sustain: 0.82,
        );
        if (env <= 0) continue;
        final double frac = (samples <= 1) ? 0.0 : i / (samples - 1);
        // Glide de afinación al ataque + pequeño bend descendente para carácter
        final double cents = (i < glideSamples)
            ? (16.0 * (1.0 - (i / math.max(1, glideSamples))))
            : 0.0;
        final double fEff =
            f0 *
            math.pow(2.0, cents / 1200.0) *
            math.pow(2.0, (bendSemis * frac) / 12.0);
        final double ph = 2 * math.pi * fEff * (t / sampleRate);
        double s = math.sin(ph);
        // Sparkle de octava muy sutil al inicio (más sutil)
        if (i < sparkleSamples) {
          final double es = 1.0 - (i / math.max(1, sparkleSamples));
          s +=
              0.06 *
              es *
              math.sin(2 * math.pi * (2.0 * fEff) * (t / sampleRate));
        }
        // Transiente de ruido muy breve
        if (i < noiseSamples) {
          final double en = 1.0 - (i / math.max(1, noiseSamples));
          s += 0.02 * en * ((rng.nextDouble() * 2.0) - 1.0);
        }
        buf[t] += env * s;
      }
    }

    // D#5 seguido de C#5 para cerrar (coherente con motivo en D# menor)
    fillBeep(startIndex: 0, samples: b1, midi: 75, bendSemis: -0.10);
    fillBeep(startIndex: b1 + gap, samples: b2, midi: 73, bendSemis: -0.22);

    // Eco sutil único (más seco)
    final int de = (0.070 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      if (i - de >= 0) buf[i] += 0.07 * buf[i - de];
    }

    // Filtros: HPF 120 Hz + LPF 6.5 kHz para coherencia
    _applyHighLowPassFilters(buf, sampleRate);

    // Normalización con headroom generoso (~ -6 dB)
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

  // Envolvente simple (attack + release), sustain opcional
  static double _adsrEnvelope(
    int i,
    int totalSamples,
    int sampleRate, {
    int attackMs = 5,
    int releaseMs = 30,
    double sustain = 1.0,
  }) {
    final a = (sampleRate * attackMs / 1000).clamp(1, totalSamples).toInt();
    final r = (sampleRate * releaseMs / 1000).clamp(1, totalSamples).toInt();
    if (i < a) {
      return i / a;
    }
    final relStart = totalSamples - r;
    if (i >= relStart) {
      final x = (i - relStart) / r;
      return (1.0 - x) * sustain;
    }
    return sustain;
  }

  /// Genera un patrón de ringback (tono + silencio) como WAV 16-bit mono
  /// Único preset: 'cyberpunk' — versión limpia con eco sutil (sin distorsión ni flanger).
  static Uint8List buildRingbackWav({
    int sampleRate = 44100,
    double durationSeconds = 2.5,
    double tempoBpm = 130.0,
  }) {
    // Nueva versión guiada por el snippet del usuario: patrón pulsado metálico por beats
    // Se genera un segmento de duración fija (default 2.5s) para poder hacer loop.
    return buildCyberRingtoneWav(
      durationSeconds: durationSeconds,
      sampleRate: sampleRate,
      tempo: tempoBpm,
    );
  }

  /// Generador principal de "CyberRingtone" (basado en el snippet del usuario)
  /// - PCM16 mono
  /// - Pulsos en cada beat + una subdivisión a medio beat
  /// - Timbre: seno + armónico + ring-mod y un toque de ruido, con envolvente A/D/R breve
  static Uint8List buildCyberRingtoneWav({
    double durationSeconds = 2.5,
    int sampleRate = 44100,
    double tempo = 130.0,
  }) {
    final int sampleCount = (durationSeconds * sampleRate).round();
    final Float64List samples = Float64List(sampleCount);

    final double beatInterval = 60.0 / tempo;
    final int samplesPerBeat = (beatInterval * sampleRate).round();

    const double baseClickFreq = 880.0;
    const double ringFreq = 1200.0;
    const double detune = 1.01;
    final math.Random rng = math.Random(12345);

    double envAtSample(int t, int onsetSample) {
      final int rel = t - onsetSample;
      if (rel < 0) return 0.0;
      final double attack = (0.005 * sampleRate); // 5 ms
      final double decay = (0.06 * sampleRate); // 60 ms
      final double release = (0.02 * sampleRate); // 20 ms
      if (rel <= attack) return rel / attack;
      if (rel <= attack + decay) {
        final double x = (rel - attack) / decay;
        return 1.0 - 0.8 * x; // cae a sustain=0.2
      }
      if (rel <= attack + decay + release) {
        final double x = (rel - (attack + decay)) / release;
        return 0.2 * (1.0 - x);
      }
      return 0.0;
    }

    for (int t = 0; t < sampleCount; t++) {
      double s = 0.0;
      final int beatIndex = (t / samplesPerBeat).floor();
      for (int k = 0; k <= 1; k++) {
        final double beatWithSubdivision = beatIndex + (k == 1 ? 0.5 : 0.0);
        final int onset = (beatWithSubdivision.round()) * samplesPerBeat;
        if (onset < 0 || onset > sampleCount) continue;
        final double a = envAtSample(t, onset);
        if (a > 0.0) {
          final double time = t / sampleRate;
          final double phase =
              2 * math.pi * baseClickFreq * (k == 0 ? 1.0 : detune) * time;
          final double carrier = math.sin(phase);
          final double harmonic = 0.5 * math.sin(2 * phase + 0.5);
          final double ring = math.sin(2 * math.pi * ringFreq * time);
          final double noise = (rng.nextDouble() * 2 - 1) * 0.002;
          s += a * (carrier + harmonic) * 0.6 * (0.7 + 0.3 * ring) + noise;
        }
      }
      samples[t] = s;
    }

    // Normalizar a peak 0.9
    double peak = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final double v = samples[i].abs();
      if (v > peak) peak = v;
    }
    final double norm = peak > 0 ? 0.9 / peak : 1.0;

    // Convertir a PCM16 y empacar WAV
    final Int16List pcm = Int16List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final int val = (samples[i] * norm * 32767.0)
          .clamp(-32768.0, 32767.0)
          .toInt();
      pcm[i] = val;
    }
    final bytes = Uint8List.view(pcm.buffer);
    return _pcm16ToWav(bytes, sampleRate: sampleRate);
  }

  /// Generador melódico (sintetizador) 2.5s: motivo breve en D# menor
  /// - Unísono ligero (detune) + armónico + ring-mod bajo para carácter
  /// - Espacial: estéreo sutil (Haas corto), pequeñas reflexiones tempranas y pan LFO leve
  static Uint8List buildMelodicRingtoneWav({
    double durationSeconds = 2.5,
    int sampleRate = 44100,
    bool stereo = true,
    double haasMs = 1.8, // retardo muy corto para efecto Haas
    double width = 0.22, // mezcla del Haas/reflexiones (0..1)
    double echo1Ms = 90.0,
    double echo2Ms = 160.0,
    double echoGain1 = 0.18,
    double echoGain2 = 0.12,
    double panLfoHz = 0.18,
    double panDepth = 0.06,
  }) {
    final int sampleCount = (durationSeconds * sampleRate).round();
    final Float64List dry = Float64List(sampleCount);

    double freqFromMidi(int midi) =>
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

    double env(double x, double noteDur) {
      // ADSR simplificada: A 4ms, D 80ms hasta 0.4, S 0.4, R 40ms
      final a = 0.004;
      final d = 0.080;
      final r = 0.040;
      if (x < 0) return 0.0;
      if (x <= a) return x / a;
      if (x <= a + d) {
        final t = (x - a) / d;
        return 1.0 - 0.6 * t; // cae a 0.4
      }
      final sustainEnd = noteDur - r;
      if (x <= sustainEnd) return 0.4;
      if (x <= noteDur) {
        final t = (x - sustainEnd) / r;
        return 0.4 * (1.0 - t);
      }
      return 0.0;
    }

    for (final n in notes) {
      final int midi = n['m']!.toInt();
      final double start = (n['start']!).toDouble();
      final double dur = (n['dur']!).toDouble();
      final int onset = (start * sampleRate).round();
      final int nsamp = (dur * sampleRate).round();
      final double f0 = freqFromMidi(midi);
      // Pequeño bend ascendente en las notas acentuadas
      final double bendSemis = (dur >= 0.30) ? 0.12 : 0.0;
      for (int i = 0; i < nsamp; i++) {
        final int t = onset + i;
        if (t < 0 || t >= sampleCount) continue;
        final double time = t / sampleRate;
        final double x = i / sampleRate;
        final double a = env(x, dur);
        if (a <= 0.0) continue;

        final double frac = (nsamp <= 1) ? 0.0 : i / (nsamp - 1);
        final double fBend = f0 * math.pow(2.0, (bendSemis * frac) / 12.0);

        // Unísono triple con leve detune
        final double p0 = 2 * math.pi * fBend * time;
        final double p1 = 2 * math.pi * (fBend * 0.994) * time;
        final double p2 = 2 * math.pi * (fBend * 1.006) * time;
        final double lead =
            (math.sin(p0) + 0.9 * math.sin(p1) + 0.9 * math.sin(p2)) / 2.8;
        final double h3 = 0.25 * math.sin(3 * p0);
        final double ring = 0.2 * math.sin(2 * math.pi * 28.0 * time);
        final double v = (lead + h3) * (0.8 + ring);
        dry[t] += a * v;
      }
    }

    // Early reflections muy suaves (2 taps globales sobre la señal seca)
    final int d1 = (echo1Ms * 0.001 * sampleRate).round();
    final int d2 = (echo2Ms * 0.001 * sampleRate).round();
    for (int i = sampleCount - 1; i >= 0; i--) {
      double v = dry[i];
      if (i - d1 >= 0) v += echoGain1 * dry[i - d1];
      if (i - d2 >= 0) v += echoGain2 * dry[i - d2];
      dry[i] = v;
    }

    // Filtro paso bajo suave (~7 kHz) para pulir y evitar aspereza
    final double fcLp = 7000.0;
    final double alphaLp =
        (2 * math.pi * fcLp) / (2 * math.pi * fcLp + sampleRate);
    double y = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      y += alphaLp * (dry[i] - y);
      dry[i] = y;
    }

    if (!stereo) {
      // Salida mono normalizada
      double peak = 0.0;
      for (int i = 0; i < sampleCount; i++) {
        final double v = dry[i].abs();
        if (v > peak) peak = v;
      }
      final double norm = peak > 0 ? 0.89 / peak : 1.0;
      final Int16List pcm = Int16List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        pcm[i] = (dry[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      }
      return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
    }

    // Estéreo sutil: canal R con pequeño retardo (Haas) y ligeras diferencias de reflexiones
    final List<double> left = List<double>.from(dry, growable: false);
    final List<double> right = List<double>.from(dry, growable: false);
    final int haas = (haasMs * 0.001 * sampleRate).round().clamp(
      0,
      sampleCount,
    );
    // Aplicar Haas en R
    for (int i = sampleCount - 1; i >= 0; i--) {
      double r = right[i];
      if (i - haas >= 0) r += width * dry[i - haas];
      right[i] = r;
    }
    // Ajustar diferencias mínimas de reflexiones
    final int d1R = (echo1Ms * 0.001 * sampleRate + 6).round().clamp(
      0,
      sampleCount,
    );
    final int d2R = (echo2Ms * 0.001 * sampleRate + 2).round().clamp(
      0,
      sampleCount,
    );
    for (int i = sampleCount - 1; i >= 0; i--) {
      double l = left[i];
      double r = right[i];
      if (i - d1 >= 0) l += (width * 0.5) * dry[i - d1];
      if (i - d2 >= 0) l += (width * 0.35) * dry[i - d2];
      if (i - d1R >= 0) r += (width * 0.5) * dry[i - d1R];
      if (i - d2R >= 0) r += (width * 0.35) * dry[i - d2R];
      left[i] = l;
      right[i] = r;
    }

    // Pan LFO muy leve (mantener casi centrado)
    if (panDepth > 0.0 && panLfoHz > 0.0) {
      for (int i = 0; i < sampleCount; i++) {
        final double t = i / sampleRate;
        final double p = math.sin(2 * math.pi * panLfoHz * t); // -1..1
        final double dl = (1.0 - panDepth * p);
        final double dr = (1.0 + panDepth * p);
        left[i] *= dl;
        right[i] *= dr;
      }
    }

    // Normalización conjunta de ambos canales
    double peak = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final double al = left[i].abs();
      final double ar = right[i].abs();
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

  /// Pad melódico largo y espacial (tipo Zimmer), 2.5 s por loop.
  /// - Triada D# menor (D#5, F#5, A#4) sostenida casi todo el segmento
  /// - Unísono con ligero detune + vibrato suave
  /// - Estéreo Haas sutil + reflexiones tempranas discretas
  /// - Filtro LPF dinámico (abre ligeramente a lo largo del segmento)
  static Uint8List buildMelodicPadRingtoneWav({
    double durationSeconds = 2.5,
    int sampleRate = 44100,
    bool stereo = true,
    double detuneCents = 4.0,
    double vibratoHz = 3.0,
    double vibratoCents = 2.0,
    double haasMs = 0.7,
    double width = 0.12,
    double echo1Ms = 140.0,
    double echo2Ms = 0.0,
    double echoGain1 = 0.06,
    double echoGain2 = 0.00,
    double lpfStartHz = 6600.0,
    double lpfEndHz = 6600.0,
  }) {
    final int N = (durationSeconds * sampleRate).round();
    final Float64List dry = Float64List(N);

    double midiHz(int m) => 440.0 * math.pow(2.0, (m - 69) / 12.0).toDouble();
    double centsToRatio(double cents) =>
        math.pow(2.0, cents / 1200.0).toDouble();

    // Triada D#m: D#5(75), F#5(78), A#4(70)
    final tones = <int>[75, 78, 70];
    final double dtn = centsToRatio(detuneCents);
    final double dtp = centsToRatio(-detuneCents);

    // Envolvente global suave (ataque breve, meseta, breve release para loop limpio)
    double envGlobal(double t) {
      final at = 0.030; // 30 ms
      final rt = 0.080; // 80 ms fade-out para evitar clicks al loop
      if (t < at) return t / at;
      if (t > durationSeconds - rt) return (durationSeconds - t) / rt;
      return 1.0;
    }

    // Render
    for (int i = 0; i < N; i++) {
      final double t = i / sampleRate;
      final double vib = centsToRatio(
        vibratoCents * math.sin(2 * math.pi * vibratoHz * t),
      );
      double acc = 0.0;
      for (final m in tones) {
        final f0 = midiHz(m) * vib;
        // Unísono triple (centro, -detune, +detune)
        final p0 = 2 * math.pi * f0 * t;
        final p1 = 2 * math.pi * (f0 * dtn) * t;
        final p2 = 2 * math.pi * (f0 * dtp) * t;
        // Mezcla con pesos para grosor moderado
        final s0 = math.sin(p0);
        final s1 = math.sin(p1);
        final s2 = math.sin(p2);
        // Armónico 3 muy sutil para no sonar afilado
        final h3 = 0.08 * math.sin(3 * p0);
        acc += (s0 + 0.9 * s1 + 0.9 * s2) / 2.8 + h3;
      }
      dry[i] = acc * 0.5 * envGlobal(t);
    }

    // High‑pass suave para evitar acumulación de bajas frecuencias
    _applyHighLowPassFilters(dry, sampleRate, lowPassHz: 0);

    // Reflexión temprana muy discreta (una sola)
    final int d1 = (echo1Ms * 0.001 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      double v = dry[i];
      if (i - d1 >= 0) v += echoGain1 * dry[i - d1];
      dry[i] = v;
    }

    // Filtro LPF (puede ser dinámico si lpfStartHz != lpfEndHz)
    final List<double> lpfOut = List<double>.filled(N, 0.0);
    double y = 0.0;
    for (int i = 0; i < N; i++) {
      final double tt = i / (N - 1).clamp(1, N);
      final double fc = (lpfStartHz == lpfEndHz)
          ? lpfStartHz
          : (lpfStartHz + (lpfEndHz - lpfStartHz) * tt);
      final double alpha = (2 * math.pi * fc) / (2 * math.pi * fc + sampleRate);
      y += alpha * (dry[i] - y);
      lpfOut[i] = y;
    }

    if (!stereo) {
      // Mono
      double peak = 0.0;
      for (int i = 0; i < N; i++) {
        final a = lpfOut[i].abs();
        if (a > peak) peak = a;
      }
      final double norm = peak > 0 ? 0.86 / peak : 1.0;
      final Int16List pcm = Int16List(N);
      for (int i = 0; i < N; i++) {
        pcm[i] = (lpfOut[i] * norm * 32767.0).clamp(-32768.0, 32767.0).toInt();
      }
      return _pcm16ToWav(Uint8List.view(pcm.buffer), sampleRate: sampleRate);
    }

    // Estéreo: Haas muy corto + ligerísima diferencia de nivel
    final List<double> L = List<double>.from(lpfOut, growable: false);
    final List<double> R = List<double>.from(lpfOut, growable: false);
    final int haas = (haasMs * 0.001 * sampleRate).round().clamp(0, N);
    for (int i = N - 1; i >= 0; i--) {
      if (i - haas >= 0) R[i] += width * lpfOut[i - haas];
    }
    // Ligera apertura por nivel
    for (int i = 0; i < N; i++) {
      L[i] *= (1.0 + width * 0.5);
      R[i] *= (1.0 - width * 0.5);
    }

    // Normalización estéreo
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

  /// Ringback melódico limpio: motivo corto + silencio para sensación de tono de llamada.
  /// - Mono 44.1 kHz para máxima compatibilidad
  /// - Motivo breve (~0.9 s) con 2-3 notas y cola corta; resto silencio hasta completar durationSeconds
  /// - Headroom amplio (norm ~ -6 dB) sin saturación en dispositivos
  static Uint8List buildMelodicRingbackWav({
    double durationSeconds = 2.5,
    int sampleRate = 44100,
  }) {
    final int N = (durationSeconds * sampleRate).round();
    final Float64List buf = Float64List(N);

    double midiHz(int m) => 440.0 * math.pow(2.0, (m - 69) / 12.0).toDouble();

    // Motivo en D# menor con todavía menos silencio y notas algo más largas
    // D#5 -> G#5 -> F#5; el motivo se extiende ~1.33 s para reducir el silencio del loop
    final notes = <Map<String, num>>[
      {'m': 75, 'start': 0.00, 'dur': 0.48, 'vel': 1.0}, // D#5
      {'m': 80, 'start': 0.40, 'dur': 0.36, 'vel': 0.95}, // G#5
      {'m': 78, 'start': 0.78, 'dur': 0.55, 'vel': 0.92}, // F#5 (más larga)
    ];

    double env(double x, double dur) {
      // Envolvente más suave: A 7ms, D 90ms a S=0.25, R 60ms
      const a = 0.007;
      const d = 0.090;
      const r = 0.060;
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

    // Síntesis de motivo (seno puro para evitar aspereza) + adornos sutiles al ataque
    for (final n in notes) {
      final int midi = n['m']!.toInt();
      final double start = (n['start']!).toDouble();
      final double dur = (n['dur']!).toDouble();
      final double vel = (n['vel']!).toDouble();
      final int onset = (start * sampleRate).round();
      final int ns = (dur * sampleRate).round();
      final double f = midiHz(midi);
      // Parámetros de adorno (más sutiles)
      final int glideSamples = (0.020 * sampleRate).round(); // ~20ms
      final int sparkleSamples = (0.040 * sampleRate).round(); // ~40ms
      final int noiseSamples = (0.012 * sampleRate).round(); // ~12ms
      final rng = math.Random(1337 + midi);
      for (int i = 0; i < ns; i++) {
        final int t = onset + i;
        if (t < 0 || t >= N) continue;
        final double x = i / sampleRate;
        final double a = env(x, dur);
        if (a <= 0.0) continue;
        // Micro-glide de +18 cents -> 0 en ~28ms
        final double cents = (i < glideSamples)
            ? (18.0 * (1.0 - (i / math.max(1, glideSamples))))
            : 0.0;
        final double fEff = f * math.pow(2.0, cents / 1200.0);
        final double ph = 2 * math.pi * fEff * (t / sampleRate);
        double s = math.sin(ph);
        // Sparkle de octava muy suave en el ataque (más sutil)
        if (i < sparkleSamples) {
          final double es = 1.0 - (i / math.max(1, sparkleSamples));
          s +=
              0.06 *
              es *
              math.sin(2 * math.pi * (2.0 * fEff) * (t / sampleRate));
        }
        // Transiente de ruido bajo nivel en el primer instante
        if (i < noiseSamples) {
          final double en = 1.0 - (i / math.max(1, noiseSamples));
          s += 0.02 * en * ((rng.nextDouble() * 2.0) - 1.0);
        }
        buf[t] += vel * a * s;
      }
    }

    // Eco único muy sutil para profundidad (tap ~120ms, -18 dB)
    final int de = (0.090 * sampleRate).round();
    for (int i = N - 1; i >= 0; i--) {
      if (i - de >= 0) buf[i] += 0.090 * buf[i - de];
    }

    // High‑pass suave (120 Hz) y Low‑pass (6.5 kHz) para limpieza
    _applyHighLowPassFilters(buf, sampleRate);

    // Fade-out suave en los últimos 30ms para un loop limpio y evitar clicks
    final int fade = (0.030 * sampleRate).round();
    for (int i = 0; i < fade; i++) {
      final int idx = N - 1 - i;
      if (idx < 0) break;
      final double g = (i / fade);
      buf[idx] *= (1.0 - g);
    }

    // Normalizar con headroom alto (~ -6 dB)
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

  /// Helper para aplicar silencio en la pausa de un doble beep
  static void _applySilenceBetweenBeeps(
    Int16List int16,
    int b1Samples,
    int gapSamples,
  ) {
    for (int i = 0; i < gapSamples; i++) {
      int16[b1Samples + i] = 0;
    }
  }

  /// Helper para llenar un beep con efectos cyberpunk (metálicos, ring-mod, bitcrush)
  static void _fillBeepCyberpunk(
    Int16List int16,
    int startIndex,
    int samples,
    double fStart,
    double fEnd,
    int sampleRate,
  ) {
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final f = fStart + (fEnd - fStart) * (i / samples);
      // base sin
      final s = math.sin(2 * math.pi * f * t);
      // armónico 3 para timbre metálico
      final h3 = 0.25 * math.sin(2 * math.pi * (f * 3) * t);
      // ring-mod lento para vibrato robótico
      final rm = math.sin(2 * math.pi * 28.0 * t);
      var mixed = (0.78 * s + 0.22 * h3) * (0.7 + 0.3 * rm);
      // ligera saturación
      mixed = mixed.clamp(-1.0, 1.0);
      mixed =
          mixed *
          (1.0 + 0.6 * (mixed.abs())) /
          (1.0 + 0.6 * (mixed.abs() * mixed.abs()));
      // bitcrush suave: cuantizar a ~8 bits
      const crushBits = 8;
      final step = 2.0 / (math.pow(2, crushBits) - 1);
      mixed = (mixed / step).round() * step;
      final env = _adsrEnvelope(
        i,
        samples,
        sampleRate,
        attackMs: 4,
        releaseMs: 40,
      );
      final amp = (32767 * 0.45 * env).round();
      int16[startIndex + i] = (amp * mixed).round();
    }
  }

  /// Helper para llenar un beep con frecuencia variable y envolvente
  static void _fillBeepBasic(
    Int16List int16,
    int startIndex,
    int samples,
    double fStart,
    double fEnd,
    int sampleRate,
    double volume,
  ) {
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final f = fStart + (fEnd - fStart) * (i / samples);
      final env = _adsrEnvelope(i, samples, sampleRate, sustain: 0.95);
      final s = math.sin(2 * math.pi * f * t);
      final sq = s >= 0 ? 1.0 : -1.0; // toque digital
      final mixed = (0.88 * s) + (0.12 * sq);
      final amp = (32767 * volume * env).round();
      int16[startIndex + i] = (amp * mixed).round();
    }
  }

  /// Helper para crear estructura de doble beep con pausa intermedia
  static ({
    int b1Samples,
    int gapSamples,
    int b2Samples,
    int total,
    Int16List int16,
  })
  _createDoubleBeepStructure({
    required int sampleRate,
    required int b1Ms,
    required int pauseMs,
    required int b2Ms,
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

  /// Helper para aplicar filtros pasa-alto y pasa-bajo a un buffer de audio
  static void _applyHighLowPassFilters(
    List<double> buffer,
    int sampleRate, {
    double highPassHz = 120.0,
    double lowPassHz = 6500.0,
  }) {
    final N = buffer.length;

    // High-pass filter (solo si highPassHz es finito y > 0)
    if (highPassHz > 0 && highPassHz.isFinite) {
      final double fcHp = highPassHz;
      final double aHp = sampleRate / (2 * math.pi * fcHp + sampleRate);
      double yHp = 0.0, xPrev = 0.0;
      for (int i = 0; i < N; i++) {
        final x = buffer[i];
        yHp = aHp * (yHp + x - xPrev);
        xPrev = x;
        buffer[i] = yHp;
      }
    }

    // Low-pass filter (solo si lowPassHz es finito y > 0)
    if (lowPassHz > 0 && lowPassHz.isFinite) {
      final double fcLp = lowPassHz;
      final double aLp =
          (2 * math.pi * fcLp) / (2 * math.pi * fcLp + sampleRate);
      double y = 0.0;
      for (int i = 0; i < N; i++) {
        y += aLp * (buffer[i] - y);
        buffer[i] = y;
      }
    }
  }

  // Empaqueta PCM16 a contenedor WAV simple
  static Uint8List _pcm16ToWav(
    Uint8List pcm, {
    required int sampleRate,
    int channels = 1,
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

  static Uint8List _le16(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  static Uint8List _le32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
}
