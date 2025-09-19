import 'dart:async';
import 'package:ai_chan/shared.dart';

/// Controlador para subtítulos sincronizados con reproducción de audio.
/// Recibe timeline opcional de palabras (startMs/endMs). Si no hay timeline
/// se puede usar revelado proporcional o texto completo instantáneo.
///
/// ✅ DDD: Refactorizado para usar Application Service
class AudioSubtitleController {
  AudioSubtitleController()
    : _applicationService = AudioSubtitleApplicationService() {
    progressiveTextStream = Stream.multi((final emitter) async {
      String last = '';
      final subs = <StreamSubscription>[];
      void emitIfChanged(final String v) {
        if (v != last) {
          last = v;
          emitter.add(v);
        }
      }

      subs.add(
        _positionStream.listen((final pos) {
          if (_manualMode) return;

          // ✅ DDD: Convert local units to Application Service format
          final timelineItems = _timeline
              .map(
                (final unit) => WordTimelineItem(
                  text: unit.text,
                  startMs: unit.startMs,
                  endMs: unit.endMs,
                  appendSpace: unit.appendSpace,
                ),
              )
              .toList();

          // ✅ DDD: Delegate to Application Service
          final progressiveText = _applicationService.generateProgressiveText(
            audioPosition: pos,
            timeline: timelineItems,
            totalDuration: _audioTotal,
          );

          emitIfChanged(progressiveText);
        }),
      );

      subs.add(
        _manualTextCtrl.stream.listen((final txt) {
          _manualMode = true;
          emitIfChanged(txt);
        }),
      );

      emitter.onCancel = () async {
        for (final s in subs) {
          try {
            await s.cancel();
          } on Exception catch (_) {}
        }
      };
    });
  }

  // ✅ DDD: Application Service dependency
  final AudioSubtitleApplicationService _applicationService;
  final _positionStreamCtrl = StreamController<Duration>.broadcast();
  final _manualTextCtrl = StreamController<String>.broadcast();
  List<WordSubtitleUnit> _timeline = [];
  Duration _audioTotal = Duration.zero;
  bool _disposed = false;
  bool _manualMode = false; // si se empuja texto manual/proporcional

  StreamSink<Duration> get _positionIn => _positionStreamCtrl.sink;
  Stream<Duration> get _positionStream => _positionStreamCtrl.stream;

  late final Stream<String> progressiveTextStream;

  void setTimeline(
    final List<WordSubtitleUnit> units, {
    required final Duration audioTotal,
  }) {
    _manualMode = false;
    _timeline = List.of(units)
      ..sort((final a, final b) => a.startMs.compareTo(b.startMs));
    _audioTotal = audioTotal;
  }

  void updatePosition(final Duration position) {
    if (_disposed) return;
    _positionIn.add(position);
  }

  void showFullTextInstant(final String text) {
    if (_disposed) return;
    _manualMode = true;
    _manualTextCtrl.add(text);
  }

  void updateProportional(
    final Duration position,
    final String fullText,
    final Duration total,
  ) {
    if (_disposed) return;
    if (fullText.isEmpty || total.inMilliseconds == 0) {
      showFullTextInstant(fullText);
      return;
    }
    _manualMode = true;
    final ratio = (position.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );

    // Mejorar cálculo para evitar subtítulos incompletos
    int targetLen;
    if (ratio >= 0.95) {
      // Si estamos cerca del final (95%), mostrar texto completo
      targetLen = fullText.length;
    } else {
      // Usar ceiling en lugar de floor para ser más inclusivo
      targetLen = (fullText.length * ratio).ceil();
    }

    final revealed = fullText.substring(0, targetLen.clamp(0, fullText.length));
    _manualTextCtrl.add(revealed);
  }

  /// Limpia texto mostrado (para reinicios de reproducción antes de conocer duración real)
  void clear() {
    if (_disposed) return;
    _manualMode = true;
    _manualTextCtrl.add('');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _positionStreamCtrl.close();
    _manualTextCtrl.close();
  }
}

class WordSubtitleUnit {
  const WordSubtitleUnit({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.appendSpace = true,
  });
  final String text;
  final int startMs;
  final int endMs;
  final bool appendSpace;
}

List<WordSubtitleUnit> buildWordTimeline({
  required final String text,
  required final Duration total,
}) {
  if (text.trim().isEmpty || total.inMilliseconds <= 0) return const [];
  final words = text.trim().split(RegExp(r'\s+'));
  final totalMs = total.inMilliseconds;
  final perWord = totalMs / words.length;
  final units = <WordSubtitleUnit>[];
  double cursor = 0;
  for (final w in words) {
    final start = cursor.round();
    final end = (cursor + perWord).round();
    units.add(WordSubtitleUnit(text: w, startMs: start, endMs: end));
    cursor += perWord;
  }
  return units;
}
