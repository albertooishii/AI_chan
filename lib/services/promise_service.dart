import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/models.dart';

/// Servicio unificado de promesas IA: detección, duplicados, restauración y scheduling.
class PromiseService {
  final List<EventEntry> events; // referencia viva a la lista de eventos global
  final VoidCallback onEventsChanged;
  final Future<void> Function(String text, {String? callPrompt, String? model}) sendSystemPrompt;

  PromiseService({required this.events, required this.onEventsChanged, required this.sendSystemPrompt});

  final List<Timer> _timers = [];

  // ================== RESTORE ==================
  void restoreFromEvents() {
    final now = DateTime.now();
    for (final e in events) {
      if (e.type == 'promesa' && e.date != null && e.date!.isAfter(now)) {
        final motivo = e.extra != null ? (e.extra!['motivo']?.toString() ?? 'promesa') : 'promesa';
        final original = e.extra != null ? (e.extra!['originalText']?.toString() ?? e.description) : e.description;
        _scheduleTimer(e.date!, motivo, original);
      }
    }
  }

  // ================== SCHEDULING ==================
  void _scheduleTimer(DateTime target, String motivo, String originalText) {
    final now = DateTime.now();
    final delay = target.difference(now);
    if (delay.inSeconds <= 0) return;
    final t = Timer(delay, () async {
      final prompt =
          'Recuerda que prometiste: "$originalText". Ya ha pasado el evento, así que cumple tu promesa ahora mismo, sin excusas. Saluda con naturalidad, menciona el motivo "$motivo" y retoma el contexto.';
      await sendSystemPrompt('', callPrompt: prompt, model: 'gemini-2.5-flash');
    });
    _timers.add(t);
  }

  void schedulePromiseEvent(EventEntry e) {
    if (e.type == 'promesa' && e.date != null && e.date!.isAfter(DateTime.now())) {
      final motivo = e.extra != null ? (e.extra!['motivo']?.toString() ?? 'promesa') : 'promesa';
      final original = e.extra != null ? (e.extra!['originalText']?.toString() ?? e.description) : e.description;
      _scheduleTimer(e.date!, motivo, original);
    }
  }

  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  // ================== DETECCIÓN ==================
  static const List<String> _keywords = [
    'clase',
    'comer',
    'trabajo',
    'baño',
    'duchar',
    'desayuno',
    'descanso',
    'hueco',
    'huequito',
    'ratito',
    'momento',
    'pausa',
    'break',
    'espacio',
    'oportunidad',
    'chance',
    'ocasión',
    'disponibilidad',
    'libre',
    'perfecto',
  ];

  bool _isDuplicated({
    String? motivo,
    DateTime? target,
    String? originalText,
    Duration window = const Duration(minutes: 10),
  }) {
    final now = DateTime.now();
    final motivoLower = motivo?.toLowerCase() ?? '';
    final originalLower = originalText?.toLowerCase().trim();
    for (final event in events) {
      if (event.type != 'promesa') continue;
      final date = event.date;
      if (date == null || !date.isAfter(now)) continue;
      final eventMotivo = event.extra?['motivo']?.toString().toLowerCase() ?? '';
      final eventOriginal = event.extra?['originalText']?.toString().toLowerCase().trim();
      if (originalLower != null && eventOriginal != null && originalLower == eventOriginal) {
        if (target != null && (date.difference(target).inMinutes).abs() <= window.inMinutes) return true;
      }
      if (motivoLower.isNotEmpty) {
        final overlap = _keywords.any((kw) => motivoLower.contains(kw) && eventMotivo.contains(kw));
        if (overlap) {
          if (target == null) return true;
          if ((date.difference(target).inMinutes).abs() <= window.inMinutes) return true;
        }
      }
    }
    return false;
  }

  void analyzeAfterIaMessage(List<Message> messages) {
    if (messages.isEmpty) return;
    final last = messages.last;
    if (last.sender != MessageSender.assistant) return;
    final text = last.text.toLowerCase();

    // 1. Hora explícita
    final regexHora = RegExp(r'(?:a las|sobre las|cuando sean las)\s*(\d{1,2})(?::(\d{2}))?');
    final matchHora = regexHora.firstMatch(text);
    final sleepWords = r'sueño|dormir|duermo|duerma|duermes|duerme|duermen|dormido|dormida|dormidas|dormidos|sleep';
    final rangoRegex = RegExp(r'(de\s*|entre\s*)(\d{1,2})(?:[:h](\d{2}))?');
    final isSleepHorario =
        (text.contains(RegExp(sleepWords, caseSensitive: false)) && rangoRegex.hasMatch(text)) ||
        (rangoRegex.hasMatch(text) && text.contains(RegExp(sleepWords, caseSensitive: false)));
    if (matchHora != null && !isSleepHorario) {
      final hour = int.tryParse(matchHora.group(1) ?? '0') ?? 0;
      final minute = int.tryParse(matchHora.group(2) ?? '0') ?? 0;
      final now = DateTime.now();
      int h = hour;
      final hasPm =
          text.contains('de la tarde') || text.contains('pm') || text.contains('p.m.') || text.contains('noche');
      final hasAm = text.contains('de la mañana') || text.contains('am') || text.contains('a.m.');
      if (hasPm && h < 12) h += 12;
      if (hasAm && h == 12) h = 0;
      DateTime target = DateTime(now.year, now.month, now.day, h, minute);
      if (target.isBefore(now)) target = target.add(const Duration(days: 1));
      const motivo = 'descanso';
      if (_isDuplicated(motivo: motivo, target: target, originalText: last.text)) return;
      events.add(
        EventEntry(
          type: 'promesa',
          description: last.text,
          date: target,
          extra: {'motivo': motivo, 'originalText': last.text},
        ),
      );
      _scheduleTimer(target, motivo, last.text);
      onEventsChanged();
      return;
    }

    // 2. Eventos comunes
    const eventos = {
      'clase': 'después de clase',
      'comer': 'cuando termine de comer',
      'trabajo': 'después del trabajo',
      'baño': 'después del baño',
      'duchar': 'después de ducharme',
      'desayuno': 'después de desayunar',
    };
    for (final key in eventos.keys) {
      if (text.contains(eventos[key]!)) {
        final now = DateTime.now();
        final target = now.add(const Duration(hours: 1));
        final motivo = key;
        if (_isDuplicated(motivo: motivo, target: target, originalText: last.text)) return;
        events.add(
          EventEntry(
            type: 'promesa',
            description: last.text,
            date: target,
            extra: {'motivo': motivo, 'originalText': last.text},
          ),
        );
        _scheduleTimer(target, motivo, last.text);
        onEventsChanged();
        return;
      }
    }

    // 3. Promesas vagas
    final regexVago = RegExp(
      r'(te aviso|te escribo|te llamo|te recuerdo|te cuento|te aviso luego|te escribo luego|te llamo luego|te lo digo luego|te lo cuento luego|te aviso en cuanto pueda|te escribo en cuanto pueda|te llamo en cuanto pueda|prometo|prometo avisar|prometo escribir|prometo llamar|prometo contar|te aviso cuando termine|te escribo cuando termine|te llamo cuando termine|te aviso cuando salga|te escribo cuando salga|te llamo cuando salga)',
      caseSensitive: false,
    );
    final condicionales = [
      'quizá',
      'intentare',
      'intentaré',
      'si puedo',
      'a lo mejor',
      'puede que',
      'probablemente',
      'posiblemente',
      'si surge',
      'si me acuerdo',
      'si tengo tiempo',
      'si se da',
      'si sale',
      'si me dejan',
      'si me da tiempo',
      'si me acuerdo te aviso',
      'si me acuerdo te escribo',
      'si me acuerdo te llamo',
    ];
    final matchVago = regexVago.firstMatch(text);
    final contieneCondicional = condicionales.any((c) => text.contains(c));
    final palabrasTiempo = [
      'mañana',
      'noche',
      'tarde',
      'por la mañana',
      'por la noche',
      'por la tarde',
      'más tarde',
      'luego',
    ];
    final contieneTiempo = palabrasTiempo.any((p) => text.contains(p));
    if (matchVago != null && !contieneCondicional && !contieneTiempo) {
      final now = DateTime.now();
      final minutosRestantes = 60 - now.minute;
      final minMin = 5;
      final maxMin = minutosRestantes > minMin ? minutosRestantes : minMin;
      final randomMinutes = minMin + (DateTime.now().millisecondsSinceEpoch % (maxMin - minMin + 1));
      final target = now.add(Duration(minutes: randomMinutes));
      final motivo = matchVago.group(0) ?? 'evento_vago';
      if (_isDuplicated(motivo: motivo, target: target, originalText: last.text)) return;
      events.add(
        EventEntry(
          type: 'promesa',
          description: last.text,
          date: target,
          extra: {'motivo': motivo, 'originalText': last.text},
        ),
      );
      _scheduleTimer(target, motivo, last.text);
      onEventsChanged();
      return;
    }
  }
}
