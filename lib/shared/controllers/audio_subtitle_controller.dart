import 'dart:async';

/// Controlador para subtítulos sincronizados con reproducción de audio.
/// Recibe timeline opcional de palabras (startMs/endMs). Si no hay timeline
/// se puede usar revelado proporcional o texto completo instantáneo.
class AudioSubtitleController {
  final _positionStreamCtrl = StreamController<Duration>.broadcast();
  final _manualTextCtrl = StreamController<String>.broadcast();
  List<WordSubtitleUnit> _timeline = [];
  Duration _audioTotal = Duration.zero;
  bool _disposed = false;
  bool _manualMode = false; // si se empuja texto manual/proporcional

  StreamSink<Duration> get _positionIn => _positionStreamCtrl.sink;
  Stream<Duration> get _positionStream => _positionStreamCtrl.stream;

  late final Stream<String> progressiveTextStream;

  AudioSubtitleController() {
    progressiveTextStream = Stream.multi((emitter) async {
      String last = '';
      final subs = <StreamSubscription>[];
      void emitIfChanged(String v) {
        if (v != last) {
          last = v;
          emitter.add(v);
        }
      }

      subs.add(
        _positionStream.listen((pos) {
          if (_manualMode) return;
          if (_timeline.isEmpty || _audioTotal.inMilliseconds <= 0) return;
          final ms = pos.inMilliseconds;
          final buf = StringBuffer();
          for (final w in _timeline) {
            if (w.startMs <= ms) {
              buf.write(w.text);
              if (w.appendSpace && !w.text.endsWith(' ')) buf.write(' ');
            } else {
              break;
            }
          }
          emitIfChanged(buf.toString().trimRight());
        }),
      );
      subs.add(
        _manualTextCtrl.stream.listen((txt) {
          _manualMode = true;
          emitIfChanged(txt);
        }),
      );
      emitter.onCancel = () async {
        for (final s in subs) {
          try {
            await s.cancel();
          } catch (_) {}
        }
      };
    });
  }

  void setTimeline(
    List<WordSubtitleUnit> units, {
    required Duration audioTotal,
  }) {
    _manualMode = false;
    _timeline = List.of(units)..sort((a, b) => a.startMs.compareTo(b.startMs));
    _audioTotal = audioTotal;
  }

  void updatePosition(Duration position) {
    if (_disposed) return;
    _positionIn.add(position);
  }

  void showFullTextInstant(String text) {
    if (_disposed) return;
    _manualMode = true;
    _manualTextCtrl.add(text);
  }

  void updateProportional(Duration position, String fullText, Duration total) {
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
    final targetLen = (fullText.length * ratio).floor();
    final revealed = fullText.substring(0, targetLen);
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
  final String text;
  final int startMs;
  final int endMs;
  final bool appendSpace;
  const WordSubtitleUnit({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.appendSpace = true,
  });
}

List<WordSubtitleUnit> buildWordTimeline({
  required String text,
  required Duration total,
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
