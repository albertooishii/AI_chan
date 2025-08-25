import 'dart:async';
import 'package:ai_chan/shared/utils/log_utils.dart';
import '../models/message.dart';
import 'package:ai_chan/core/models/ai_chan_profile.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ai_chan/shared/utils/schedule_utils.dart';

/// Servicio que gestiona el envío periódico de mensajes IA automáticos
/// aplicando las mismas reglas que estaban embebidas en ChatProvider.
class PeriodicIaMessageScheduler {
  Timer? _timer;
  int _autoStreak = 0; // racha de autos sin respuesta
  DateTime? _lastAutoIa; // último envío automático efectivo
  bool get isRunning => _timer != null;

  void start({
    required AiChanProfile Function() profileGetter,
    required List<Message> Function() messagesGetter,
    required void Function(String callPrompt, String model) triggerSend,
    Duration? initialDelay,
  }) {
    stop();
    Log.i('Iniciando scheduler de mensajes automáticos IA', tag: 'PERIODIC_IA');

    void scheduleNext([int? prevIntervalMin]) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final intervalMin = 25 + (nowMs % 16); // 25-40
      final interval = Duration(minutes: intervalMin);
      _timer = Timer(interval, () {
        final profile = profileGetter();
        final messages = messagesGetter();
        final now = DateTime.now();
        final tipo = _getCurrentScheduleType(now, profile);
        Log.d('Timer @ ${now.toIso8601String()} tipo=$tipo', tag: 'PERIODIC_IA');
        if (tipo != 'sleep' && tipo != 'work' && tipo != 'busy') {
          final lastMsg = messages.isNotEmpty ? messages.last : null;
          final lastMsgTime = lastMsg?.dateTime;
          final diffMinutes = lastMsgTime != null ? now.difference(lastMsgTime).inMinutes : 9999;
          final streak = _autoStreak;
          // Base 60 + 60 por cada auto extra (cap 8h) => mismo comportamiento original
          final minWait = (60 + (streak > 0 ? (streak * 60) : 0)).clamp(60, 480);
          final cooldownOk = _lastAutoIa == null || now.difference(_lastAutoIa!).inMinutes >= 30;
          if (diffMinutes >= minWait && cooldownOk) {
            final prompts = _autoPrompts();
            final idx = nowMs % prompts.length;
            final callPrompt = prompts[idx];
            final textModel = dotenv.env['DEFAULT_TEXT_MODEL'] ?? '';
            triggerSend(callPrompt, textModel);
            _lastAutoIa = now;
            _autoStreak = (_autoStreak + 1).clamp(0, 20);
          } else {
            Log.d('Skip auto diff=$diffMinutes minWait=$minWait cooldown=$cooldownOk', tag: 'PERIODIC_IA');
          }
        } else {
          Log.d('Skip por horario: $tipo', tag: 'PERIODIC_IA');
        }
        scheduleNext(intervalMin);
      });
    }

    if (initialDelay != null) {
      _timer = Timer(initialDelay, () => scheduleNext());
    } else {
      scheduleNext();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();

  // ------- Helpers -------
  List<String> _autoPrompts() => const [
    'Saluda brevemente con un toque cariñoso y comenta el momento del día o algo del historial. Evita plantillas y sé espontánea. Si el silencio es largo, muestra paciencia sin insistir.',
    'Envía un mensaje corto y cercano, con curiosidad suave por el silencio. Relaciónalo con la hora o un detalle reciente. Nada de frases hechas ni repetirte.',
    'Escribe un saludo natural y tierno, acorde a tu personalidad y al contexto. Si lleva mucho sin responder, empatiza y espera sin presionar.',
    'Muestra una emoción sutil (humor, ternura o interés) ajustada al momento. Conecta con alguna anécdota reciente del chat. Evita sonar robótica o usar plantillas.',
    'Un mensajito breve y cálido, con un guiño al día/hora. Si ya has escrito antes sin respuesta, baja el ritmo y transmite calma.',
  ];

  String? _getCurrentScheduleType(DateTime now, AiChanProfile profile) {
    final bio = profile.biography;
    final int currentMinutes = now.hour * 60 + now.minute;

    bool inRange(Map m) {
      final String from = (m['from']?.toString() ?? '');
      final String to = (m['to']?.toString() ?? '');
      final res = ScheduleUtils.isTimeInRange(currentMinutes: currentMinutes, from: from, to: to);
      return res ?? false;
    }

    bool dayMatches(dynamic dias) {
      final raw = dias?.toString() ?? '';
      final spec = ScheduleUtils.parseScheduleString(raw);
      return ScheduleUtils.matchesDateWithInterval(now, spec);
    }

    try {
      final dormir = bio['horario_dormir'];
      if (dormir is Map && inRange(dormir)) return 'sleep';

      final trabajo = bio['horario_trabajo'];
      if (trabajo is Map && dayMatches(trabajo['dias']) && inRange(trabajo)) {
        return 'work';
      }

      final estudio = bio['horario_estudio'];
      if (estudio is Map && dayMatches(estudio['dias']) && inRange(estudio)) {
        return 'work';
      }

      final actividades = bio['horarios_actividades'];
      if (actividades is List) {
        for (final a in actividades) {
          if (a is Map && dayMatches(a['dias']) && inRange(a)) return 'busy';
        }
      }
    } catch (_) {}
    return null;
  }

  /// Determina si se debe enviar un mensaje automático (para compatibilidad)
  bool shouldSendAutomaticMessage(List<Message> messages, AiChanProfile profile) {
    final now = DateTime.now();
    final tipo = _getCurrentScheduleType(now, profile);
    if (tipo == 'sleep' || tipo == 'work' || tipo == 'busy') {
      return false;
    }

    final lastMsg = messages.isNotEmpty ? messages.last : null;
    final lastMsgTime = lastMsg?.dateTime;
    final diffMinutes = lastMsgTime != null ? now.difference(lastMsgTime).inMinutes : 9999;

    final minWait = (60 + (_autoStreak > 0 ? (_autoStreak * 60) : 0)).clamp(60, 480);
    final cooldownOk = _lastAutoIa == null || now.difference(_lastAutoIa!).inMinutes >= 30;

    return diffMinutes >= minWait && cooldownOk;
  }

  /// Analiza el horario y determina si debe enviar un mensaje (para compatibilidad)
  bool shouldSendScheduledMessage(AiChanProfile profile) {
    return false; // La lógica principal ahora está en start()
  }
}
