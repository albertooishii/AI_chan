import 'dart:async';

/// Servicio que gestiona el envío periódico de mensajes IA automáticos
/// aplicando las mismas reglas que estaban embebidas en ChatProvider.
class PeriodicIaMessageScheduler {
  Timer? _timer;
  int _autoStreak = 0; // racha de autos sin respuesta
  DateTime? _lastAutoIa; // último envío automático efectivo
  bool get isRunning => _timer != null;

  void start({
    required final Map<String, dynamic> Function() profileGetter,
    required final List<Map<String, dynamic>> Function() messagesGetter,
    required final void Function(String callPrompt)
    triggerSend, // Removed model parameter
    final Duration? initialDelay,
  }) {
    stop();

    void scheduleNext([final int? prevIntervalMin]) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final intervalMin = 25 + (nowMs % 16); // 25-40
      final interval = Duration(minutes: intervalMin);
      _timer = Timer(interval, () {
        final profile = profileGetter();
        final messages = messagesGetter();
        final now = DateTime.now();
        final tipo = _getCurrentScheduleType(now, profile);
        if (tipo != 'sleep' && tipo != 'work' && tipo != 'busy') {
          final lastMsg = messages.isNotEmpty ? messages.last : null;
          final lastMsgTime = lastMsg?['dateTime'] as DateTime?;
          final diffMinutes = lastMsgTime != null
              ? now.difference(lastMsgTime).inMinutes
              : 9999;
          final streak = _autoStreak;
          // Base 60 + 60 por cada auto extra (cap 8h) => mismo comportamiento original
          final minWait = (60 + (streak > 0 ? (streak * 60) : 0)).clamp(
            60,
            480,
          );
          final cooldownOk =
              _lastAutoIa == null ||
              now.difference(_lastAutoIa!).inMinutes >= 30;
          if (diffMinutes >= minWait && cooldownOk) {
            final prompts = _autoPrompts();
            final idx = nowMs % prompts.length;
            final callPrompt = prompts[idx];
            triggerSend(callPrompt); // Model selection is now automatic
            _lastAutoIa = now;
            _autoStreak = (_autoStreak + 1).clamp(0, 20);
          }
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

  String? _getCurrentScheduleType(
    final DateTime now,
    final Map<String, dynamic> profile,
  ) {
    final bio = profile['biography'] as Map<String, dynamic>? ?? {};
    final int currentMinutes = now.hour * 60 + now.minute;

    bool inRange(final Map<String, dynamic> m) {
      final String from = (m['from']?.toString() ?? '');
      final String to = (m['to']?.toString() ?? '');
      return _isTimeInRange(currentMinutes: currentMinutes, from: from, to: to);
    }

    bool dayMatches(final dynamic dias) {
      final raw = dias?.toString() ?? '';
      final spec = _parseScheduleString(raw);
      return _matchesDateWithInterval(now, spec);
    }

    try {
      final dormir = bio['horario_dormir'];
      if (dormir is Map<String, dynamic> && inRange(dormir)) return 'sleep';

      final trabajo = bio['horario_trabajo'];
      if (trabajo is Map<String, dynamic> &&
          dayMatches(trabajo['dias']) &&
          inRange(trabajo)) {
        return 'work';
      }

      final estudio = bio['horario_estudio'];
      if (estudio is Map<String, dynamic> &&
          dayMatches(estudio['dias']) &&
          inRange(estudio)) {
        return 'work';
      }

      final actividades = bio['horarios_actividades'];
      if (actividades is List) {
        for (final a in actividades) {
          if (a is Map<String, dynamic> &&
              dayMatches(a['dias']) &&
              inRange(a)) {
            return 'busy';
          }
        }
      }
    } on Exception catch (_) {}
    return null;
  }

  bool _isTimeInRange({
    required final int currentMinutes,
    required final String from,
    required final String to,
  }) {
    try {
      final fromParts = from.split(':');
      final toParts = to.split(':');
      if (fromParts.length != 2 || toParts.length != 2) return false;

      final fromMin = int.parse(fromParts[0]) * 60 + int.parse(fromParts[1]);
      final toMin = int.parse(toParts[0]) * 60 + int.parse(toParts[1]);

      if (fromMin <= toMin) {
        return currentMinutes >= fromMin && currentMinutes <= toMin;
      } else {
        // Cross midnight
        return currentMinutes >= fromMin || currentMinutes <= toMin;
      }
    } on Exception catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _parseScheduleString(final String raw) {
    if (raw.trim().isEmpty) {
      return {'type': 'all', 'days': <int>[]};
    }

    final lower = raw.toLowerCase().trim();
    final days = <int>[];

    // Parse individual days
    if (lower.contains('lun')) days.add(DateTime.monday);
    if (lower.contains('mar')) days.add(DateTime.tuesday);
    if (lower.contains('mié') || lower.contains('mie')) {
      days.add(DateTime.wednesday);
    }
    if (lower.contains('jue')) days.add(DateTime.thursday);
    if (lower.contains('vie')) days.add(DateTime.friday);
    if (lower.contains('sáb') || lower.contains('sab')) {
      days.add(DateTime.saturday);
    }
    if (lower.contains('dom')) days.add(DateTime.sunday);

    // Parse ranges
    if (lower.contains('lun-vie') || lower.contains('lunes-viernes')) {
      days.addAll([1, 2, 3, 4, 5]);
    }
    if (lower.contains('lun-sáb') || lower.contains('lunes-sábado')) {
      days.addAll([1, 2, 3, 4, 5, 6]);
    }
    if (lower.contains('lun-dom') || lower.contains('lunes-domingo')) {
      days.addAll([1, 2, 3, 4, 5, 6, 7]);
    }

    return {
      'type': days.isEmpty ? 'none' : 'specific',
      'days': days.toSet().toList(),
    };
  }

  bool _matchesDateWithInterval(
    final DateTime now,
    final Map<String, dynamic> spec,
  ) {
    final type = spec['type'] as String? ?? 'all';
    if (type == 'all') return true;
    if (type == 'none') return false;

    final days = (spec['days'] as List<dynamic>? ?? []).cast<int>();
    return days.contains(now.weekday);
  }

  /// Determina si se debe enviar un mensaje automático (para compatibilidad)
  bool shouldSendAutomaticMessage(
    final List<Map<String, dynamic>> messages,
    final Map<String, dynamic> profile,
  ) {
    final now = DateTime.now();
    final tipo = _getCurrentScheduleType(now, profile);
    if (tipo == 'sleep' || tipo == 'work' || tipo == 'busy') {
      return false;
    }

    final lastMsg = messages.isNotEmpty ? messages.last : null;
    final lastMsgTime = lastMsg?['dateTime'] as DateTime?;
    final diffMinutes = lastMsgTime != null
        ? now.difference(lastMsgTime).inMinutes
        : 9999;

    final minWait = (60 + (_autoStreak > 0 ? (_autoStreak * 60) : 0)).clamp(
      60,
      480,
    );
    final cooldownOk =
        _lastAutoIa == null || now.difference(_lastAutoIa!).inMinutes >= 30;

    return diffMinutes >= minWait && cooldownOk;
  }

  /// Analiza el horario y determina si debe enviar un mensaje (para compatibilidad)
  bool shouldSendScheduledMessage(final Map<String, dynamic> profile) {
    return false; // La lógica principal ahora está en start()
  }
}
