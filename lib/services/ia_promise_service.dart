// import eliminado porque no se usa
import 'package:ai_chan/utils/log_utils.dart';
import '../models/message.dart';
import '../models/event_entry.dart';

class IaPromiseService {
  /// Restaura promesas desde EventEntry guardados previamente
  static void restoreFromEventEntries({
    required List<EventEntry> events,
    required void Function(DateTime, String, String) scheduleIaPromise,
  }) {
    final now = DateTime.now();
    for (final e in events) {
      if (e.type == 'promesa' && e.date != null && e.date!.isAfter(now)) {
        final motivo = e.extra != null ? (e.extra!['motivo']?.toString() ?? 'promesa') : 'promesa';
        final original = e.extra != null ? (e.extra!['originalText']?.toString() ?? e.description) : e.description;
        scheduleIaPromise(e.date!, motivo, original);
      }
    }
  }

  /// Restaura eventos IA desde una lista JSON y programa recordatorios
  static void restoreIaPromiseEvents({
    required List<dynamic> eventsList,
    required List<IaPromiseEvent> iaPromiseEvents,
    required void Function(DateTime, String, String) scheduleIaPromise,
  }) {
    iaPromiseEvents.clear();
    for (var e in eventsList) {
      final event = IaPromiseEvent.fromJson(e);
      if (event.targetTime.isAfter(DateTime.now())) {
        iaPromiseEvents.add(event);
        scheduleIaPromise(event.targetTime, event.motivo, event.originalText);
      }
    }
  }

  /// Analiza el último mensaje de la IA y programa recordatorios si detecta promesas
  static const List<String> iaKeywords = [
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

  static bool isIaPromiseDuplicated(
    List<EventEntry> events, {
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
      // 1) Mismo originalText y hora cercana
      if (originalLower != null && eventOriginal != null && originalLower == eventOriginal) {
        if (target != null && (date.difference(target).inMinutes).abs() <= window.inMinutes) {
          return true;
        }
      }
      // 2) Motivo similar según keywords y hora cercana (si se pasa target)
      if (motivoLower.isNotEmpty) {
        final motivoOverlap = iaKeywords.any((kw) => motivoLower.contains(kw) && eventMotivo.contains(kw));
        if (motivoOverlap) {
          if (target == null) {
            return true; // mismo motivo futuro sin comparar hora
          }
          if ((date.difference(target).inMinutes).abs() <= window.inMinutes) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static void analyzeIaPromises({
    required List<Message> messages,
    required List<EventEntry> events,
    required void Function(DateTime target, String motivo, String originalText) scheduleIaPromise,
  }) {
    if (messages.isEmpty) return;
    final lastMsg = messages.last;
    if (lastMsg.sender != MessageSender.assistant) return;
    final text = lastMsg.text.toLowerCase();
    final regexHora = RegExp(r'(?:a las|sobre las|cuando sean las)\s*(\d{1,2})(?::(\d{2}))?');
    final matchHora = regexHora.firstMatch(text);
    final sleepWords = r'sueño|dormir|duermo|duerma|duermes|duerme|duermen|dormido|dormida|dormidas|dormidos|sleep';
    final rangoRegex = RegExp(
      r'(de\s*|entre\s*)?(\d{1,2})(?:[:h](\d{2}))?\s*(de la mañana|am|a\.m\.|de la tarde|pm|p\.m\.|tarde|mañana)?\s*(a|y)\s*(las\s*)?(\d{1,2})(?:[:h](\d{2}))?\s*(de la mañana|am|a\.m\.|de la tarde|pm|p\.m\.|tarde|mañana)?',
      caseSensitive: false,
    );
    final isSleepHorario =
        (text.contains(RegExp(sleepWords, caseSensitive: false)) && rangoRegex.hasMatch(text)) ||
        (rangoRegex.hasMatch(text) && text.contains(RegExp(sleepWords, caseSensitive: false)));
    if (matchHora != null && !isSleepHorario) {
      final hour = int.tryParse(matchHora.group(1) ?? '0') ?? 0;
      final minute = int.tryParse(matchHora.group(2) ?? '0') ?? 0;
      final now = DateTime.now();
      int h = hour;
      // Ajuste simple AM/PM a partir del texto
      final lower = text.toLowerCase();
      final hasPm =
          lower.contains('de la tarde') || lower.contains('pm') || lower.contains('p.m.') || lower.contains('noche');
      final hasAm = lower.contains('de la mañana') || lower.contains('am') || lower.contains('a.m.');
      if (hasPm && h < 12) h += 12;
      if (hasAm && h == 12) h = 0;
      DateTime target = DateTime(now.year, now.month, now.day, h, minute);
      if (target.isBefore(now)) target = target.add(const Duration(days: 1));
      final motivo = 'descanso';
      if (isIaPromiseDuplicated(events, motivo: motivo, target: target, originalText: lastMsg.text)) {
        Log.w('[PROMESA IA] Evento duplicado detectado para motivo "$motivo". No se programa de nuevo.');
        return;
      }
      Log.i('[PROMESA IA] Detectada promesa de hora: "${lastMsg.text}" para las $hour:$minute ($target)');
      events.add(
        EventEntry(
          type: 'promesa',
          description: lastMsg.text,
          date: target,
          extra: {'motivo': motivo, 'originalText': lastMsg.text},
        ),
      );
      scheduleIaPromise(target, motivo, lastMsg.text);
      return;
    }
    final eventos = {
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
        if (isIaPromiseDuplicated(events, motivo: motivo, target: target, originalText: lastMsg.text)) {
          Log.w('[PROMESA IA] Evento duplicado detectado para motivo "$motivo". No se programa de nuevo.');
          return;
        }
        Log.i(
          '[PROMESA IA] Detectada promesa de evento: "${lastMsg.text}" para "$key" (ejecutar a las ${target.hour}:${target.minute} - $target)',
        );
        events.add(
          EventEntry(
            type: 'promesa',
            description: lastMsg.text,
            date: target,
            extra: {'motivo': motivo, 'originalText': lastMsg.text},
          ),
        );
        scheduleIaPromise(target, motivo, lastMsg.text);
        return;
      }
    }
    // Filtro de promesas vagas: solo si hay verbo de acción futura y no es condicional
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
      'si me acuerdo',
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
      final minMinutos = 5;
      final maxMinutos = minutosRestantes > minMinutos ? minutosRestantes : minMinutos;
      final randomMinutes = minMinutos + (DateTime.now().millisecondsSinceEpoch % (maxMinutos - minMinutos + 1));
      final target = now.add(Duration(minutes: randomMinutes));
      final motivo = matchVago.group(0) ?? 'evento_vago';
      if (isIaPromiseDuplicated(events, motivo: motivo, target: target, originalText: lastMsg.text)) {
        Log.w('[PROMESA IA] Evento duplicado detectado para motivo "$motivo". No se programa de nuevo.');
        return;
      }
      Log.i(
        '[PROMESA IA] Detectada promesa vaga de tiempo: "${lastMsg.text}" para "$motivo" (ejecutar en $randomMinutes minutos, a las ${target.hour}:${target.minute} - $target)',
      );
      events.add(
        EventEntry(
          type: 'promesa',
          description: lastMsg.text,
          date: target,
          extra: {'motivo': motivo, 'originalText': lastMsg.text},
        ),
      );
      scheduleIaPromise(target, motivo, lastMsg.text);
      return;
    }
  }
}

class IaPromiseEvent {
  final DateTime targetTime;
  final String motivo;
  final String originalText;
  IaPromiseEvent(this.targetTime, this.motivo, this.originalText);

  Map<String, dynamic> toJson() => {
    'targetTime': targetTime.toIso8601String(),
    'motivo': motivo,
    'originalText': originalText,
  };

  static IaPromiseEvent fromJson(Map<String, dynamic> json) {
    return IaPromiseEvent(
      DateTime.parse(json['targetTime'] as String),
      json['motivo'] as String,
      json['originalText'] as String,
    );
  }
}
