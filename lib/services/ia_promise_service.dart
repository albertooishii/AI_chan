import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/event_entry.dart';

class IaPromiseService {
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

  static bool isIaPromiseDuplicated(List<EventEntry> events, String motivo) {
    final now = DateTime.now();
    final motivoLower = motivo.toLowerCase();
    for (final event in events) {
      if (event.date != null && event.date!.isAfter(now)) {
        final eventMotivo = event.extra?['motivo']?.toString().toLowerCase() ?? '';
        for (final kw in iaKeywords) {
          if (motivoLower.contains(kw) && eventMotivo.contains(kw)) {
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
    if (lastMsg.sender.toString() != 'MessageSender.ia') return;
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
      DateTime target = DateTime(now.year, now.month, now.day, hour, minute);
      if (target.isBefore(now)) target = target.add(const Duration(days: 1));
      final motivo = 'descanso';
      if (isIaPromiseDuplicated(events, motivo)) {
        debugPrint('[PROMESA IA] Evento duplicado detectado para motivo "$motivo". No se programa de nuevo.');
        return;
      }
      debugPrint('[PROMESA IA] Detectada promesa de hora: "${lastMsg.text}" para las $hour:$minute ($target)');
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
        if (isIaPromiseDuplicated(events, motivo)) {
          debugPrint('[PROMESA IA] Evento duplicado detectado para motivo "$motivo". No se programa de nuevo.');
          return;
        }
        debugPrint(
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
    final regexVago = RegExp(
      r'('
      r'en la próxima hora|'
      r'cuando\s+((tenga|me quede|disponga de|pueda|esté|haya|me libere|me desocupe|acabe|termine|finalice|salga|vea|surja|encuentre|acabe aquí|termine aquí|termine en el trabajo|termine en la oficina|salga de la oficina|salga del trabajo|ponga un pie fuera|me marche|me vaya|me escape|me desocupe|me libere)(\s*(y|o|,)?\s*)?)+[^\n]{0,40}?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|oportunidad|chance|ocasión|disponibilidad|libre|perfecto)?(\s*libre)?|'
      r'en cuanto\s+((pueda|tenga|me quede|disponga de|esté|haya|me libere|me desocupe|vea|surja|encuentre|acabe aquí|termine aquí|termine en el trabajo|termine en la oficina|salga de la oficina|salga del trabajo|ponga un pie fuera|me marche|me vaya|me escape)(\s*(y|o|,)?\s*)?)+[^\n]{0,40}?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|oportunidad|chance|ocasión|disponibilidad|libre|perfecto)?(\s*libre)?|'
      r'deseando que llegue[^\n]*?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|perfecto)|'
      r'esperando[^\n]*?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|perfecto)|'
      r'que llegue[^\n]*?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|perfecto)|'
      r'en cuanto salga de (la oficina|el trabajo|a la calle)|'
      r'en cuanto ponga un pie fuera|'
      r'en cuanto termine aquí|'
      r'en cuanto acabe aquí|'
      r'en cuanto me marche|'
      r'en cuanto me vaya|'
      r'en cuanto me escape|'
      r'en cuanto me desocupe|'
      r'en cuanto me libere|'
      r'cuando salga de (la oficina|el trabajo|a la calle)|'
      r'cuando ponga un pie fuera|'
      r'cuando termine aquí|'
      r'cuando acabe aquí|'
      r'cuando me marche|'
      r'cuando me vaya|'
      r'cuando me escape|'
      r'cuando me desocupe|'
      r'cuando me libere|'
      r'en un minutito salgo|'
      r'ya estoy saliendo|'
      r'estoy por salir|'
      r'recogiendo mis cosas|'
      r'ya casi salgo|'
      r'ya me voy|'
      r'estoy saliendo|'
      r'qué ganas de llegar a casa|'
      r'ya voy en camino|'
      r'voy para allá|'
      r'ya estoy en camino'
      r')',
      caseSensitive: false,
    );
    final matchVago = regexVago.firstMatch(text);
    if (matchVago != null) {
      final now = DateTime.now();
      final minutosRestantes = 60 - now.minute;
      final minMinutos = 5;
      final maxMinutos = minutosRestantes > minMinutos ? minutosRestantes : minMinutos;
      final randomMinutes = minMinutos + (DateTime.now().millisecondsSinceEpoch % (maxMinutos - minMinutos + 1));
      final target = now.add(Duration(minutes: randomMinutes));
      final motivo = matchVago.group(0) ?? 'evento_vago';
      if (isIaPromiseDuplicated(events, motivo)) {
        debugPrint('[PROMESA IA] Evento duplicado detectado para motivo "$motivo". No se programa de nuevo.');
        return;
      }
      debugPrint(
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
