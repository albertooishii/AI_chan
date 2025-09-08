import 'package:ai_chan/core/models.dart';
import '../../utils/event_parser_utils.dart';
import '../../utils/log_utils.dart';

class EventTimelineService {
  // Añade un evento al timeline si se detecta fecha y palabras clave
  static TimelineEntry? createEventFromText(final String text) {
    final date = EventParserUtils.parseFullDate(text);
    if (date != null && EventParserUtils.containsEventKeywords(text)) {
      // Extraer la frase más larga y significativa del texto
      final frases = text
          .split(RegExp(r'[\.\n!?]'))
          .map((final f) => f.trim())
          .where((final f) => f.isNotEmpty)
          .toList();
      // Elegir la frase más larga (probablemente el nombre del evento)
      String descripcionEvento = frases.isNotEmpty
          ? frases.reduce((final a, final b) => a.length >= b.length ? a : b)
          : 'Evento';
      // Limpiar markdown y caracteres especiales
      descripcionEvento = descripcionEvento
          .replaceAll(RegExp(r'\*|\_|\#|\-|\`|\>|\[|\]|\(|\)|\:|\;'), '')
          .trim();
      // Detectar hora explícita como '7 de la tarde', '8 pm', etc.
      final horaExplicita = RegExp(
        r'(\d{1,2})\s*(?:[:h](\d{2}))?\s*(de la tarde|pm|p\.m\.|tarde|de la noche|noche|am|a\.m\.|mañana)?',
        caseSensitive: false,
      );
      final match = horaExplicita.firstMatch(text);
      int hour = 0;
      int minute = 0;
      if (match != null) {
        hour = int.tryParse(match.group(1) ?? '0') ?? 0;
        minute = int.tryParse(match.group(2) ?? '0') ?? 0;
        final periodo = (match.group(3) ?? '').toLowerCase();
        if (periodo.contains('tarde') ||
            periodo.contains('pm') ||
            periodo.contains('p.m.') ||
            periodo.contains('noche')) {
          if (hour < 12) hour += 12;
        }
        // Si es mañana/am y la hora es 12, mantener 12am
      } else {
        // Si no hay hora explícita, usar aproximación por palabras clave
        if (text.toLowerCase().contains('mañana')) {
          hour = 9;
        } else if (text.toLowerCase().contains('tarde')) {
          hour = 18;
        } else if (text.toLowerCase().contains('noche')) {
          hour = 21;
        }
      }
      DateTime dateWithHour = date;
      if (hour > 0 || minute > 0) {
        dateWithHour = DateTime(date.year, date.month, date.day, hour, minute);
      }
      final startDate = dateWithHour.toIso8601String();
      return TimelineEntry(
        resume: descripcionEvento,
        startDate: startDate,
        level: 1,
      );
    }
    return null;
  }

  /// Detecta y guarda automáticamente eventos/citas y horarios en el perfil
  static Future<dynamic> detectAndSaveEventAndSchedule({
    required final String text,
    required final String textResponse,
    required dynamic onboardingData,
    required final Future<void> Function() saveAll,
  }) async {
    // --- EVENTOS/CITAS ---
    final eventEntry = createEventFromText(textResponse);
    if (eventEntry != null) {
      // Convertir TimelineEntry a EventEntry y guardar en events
      final List<EventEntry> updatedEvents = onboardingData.events != null
          ? List<EventEntry>.from(onboardingData.events)
          : <EventEntry>[];
      // Usar la frase significativa extraída por createEventFromText
      final descripcionNatural = eventEntry.resume;
      final DateTime? eventDate =
          (eventEntry.startDate != null && eventEntry.startDate != '')
          ? DateTime.parse(eventEntry.startDate!)
          : null;
      bool isDuplicate = false;
      for (final ev in updatedEvents) {
        final sameDesc =
            ev.description.trim().toLowerCase() ==
            descripcionNatural.trim().toLowerCase();
        final sameDay =
            ev.date != null &&
            eventDate != null &&
            ev.date!.year == eventDate.year &&
            ev.date!.month == eventDate.month &&
            ev.date!.day == eventDate.day;
        final closeInTime =
            ev.date != null &&
            eventDate != null &&
            (ev.date!.difference(eventDate).inMinutes).abs() <= 120;
        if (ev.type == 'evento' && sameDesc && (sameDay || closeInTime)) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        updatedEvents.add(
          EventEntry(
            type: 'evento',
            description: descripcionNatural,
            date: eventDate,
          ),
        );
        onboardingData = onboardingData.copyWith(events: updatedEvents);
        await saveAll();
        Log.d(
          'Guardado evento en events: $descripcionNatural (${eventEntry.startDate})',
          tag: 'EVENTO_IA',
        );
      } else {
        Log.d(
          'Evento duplicado detectado. No se guarda: $descripcionNatural (${eventEntry.startDate})',
          tag: 'EVENTO_IA',
        );
      }
    }

    // --- HORARIOS ---
    final regexVagoCheck = RegExp(
      r'(en la próxima hora|cuando\s+((tenga|me quede|disponga de|pueda|esté|haya|me libere|me desocupe|acabe|termine|finalice|salga|vea|surja|encuentre)(\s*(y|o|,)?\s*)?)+[^\n]{0,40}?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|oportunidad|chance|ocasión|disponibilidad|libre|perfecto)?(\s*libre)?|en cuanto\s+((pueda|tenga|me quede|disponga de|esté|haya|me libere|me desocupe|vea|surja|encuentre)(\s*(y|o|,)?\s*)?)+[^\n]{0,40}?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|oportunidad|chance|ocasión|disponibilidad|libre|perfecto)?(\s*libre)?|deseando que llegue[^\n]*?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|perfecto)|esperando[^\n]*?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|perfecto)|que llegue[^\n]*?(hueco|huequito|ratito|momento|pausa|break|descanso|espacio|perfecto))',
      caseSensitive: false,
    );
    final diasRegex = RegExp(
      r'((de|los|solo|excepto|menos)?\s*(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)(\s*(a|hasta|y|,|-)?\s*(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo))*)',
      caseSensitive: false,
    );
    final rangoRegex = RegExp(
      r'(de\s*|entre\s*)?(\d{1,2})(?:[:h](\d{2}))?\s*(de la mañana|am|a\.m\.|de la tarde|pm|p\.m\.|tarde|mañana)?\s*(a|y)\s*(las\s*)?(\d{1,2})(?:[:h](\d{2}))?\s*(de la mañana|am|a\.m\.|de la tarde|pm|p\.m\.|tarde|mañana)?',
      caseSensitive: false,
    );
    final sleepWords =
        r'sueño|dormir|duermo|duerma|duermes|duerme|duermen|dormido|dormida|dormidas|dormidos|sleep';
    final workWords = r'trabajo|work';
    final busyWords =
        r'ocupada|ocupación|busy|gimnasio|gym|compras|reunión|reunion|cita|viaje|deporte|actividad|evento|tarea|proyecto';
    final studyWords =
        r'estudio|estudiar|clase|universidad|escuela|facultad|tutoría|tutoria|asignatura|examen|prácticas|practicas';
    final preguntaSleep = text.contains(
      RegExp(sleepWords, caseSensitive: false),
    );
    final respuestaSleep = textResponse.contains(
      RegExp(sleepWords, caseSensitive: false),
    );
    final respuestaWork = textResponse.contains(
      RegExp(workWords, caseSensitive: false),
    );
    final respuestaBusy = textResponse.contains(
      RegExp(busyWords, caseSensitive: false),
    );
    final diasMatch = diasRegex.firstMatch(textResponse);
    final rangoMatch = rangoRegex.firstMatch(textResponse);
    if (!regexVagoCheck.hasMatch(textResponse) && rangoMatch != null) {
      String tipoHorario = '';
      if (respuestaSleep) {
        tipoHorario = 'sleep';
      } else if (respuestaWork) {
        tipoHorario = 'work';
      } else if (textResponse.contains(
        RegExp(studyWords, caseSensitive: false),
      )) {
        tipoHorario = 'study';
      } else if (respuestaBusy) {
        tipoHorario = 'busy';
      } else {
        if (preguntaSleep) {
          tipoHorario = 'sleep';
        } else if (text.contains(RegExp(workWords, caseSensitive: false))) {
          tipoHorario = 'work';
        } else if (text.contains(RegExp(studyWords, caseSensitive: false))) {
          tipoHorario = 'study';
        } else if (text.contains(RegExp(busyWords, caseSensitive: false))) {
          tipoHorario = 'busy';
        }
      }
      Log.d(
        'Intentando extraer días: ${diasMatch != null ? diasMatch.group(0) : 'NO DETECTADO'}',
        tag: 'HORARIO_IA',
      );
      Log.d(
        'Intentando extraer rango de horas: ${rangoMatch.group(0)}',
        tag: 'HORARIO_IA',
      );
      if (tipoHorario.isNotEmpty) {
        final String fromHour = rangoMatch.group(2) ?? '';
        final String fromMin = rangoMatch.group(3) ?? '00';
        final String fromPeriod = (rangoMatch.group(4) ?? '').toLowerCase();
        final String toHour = rangoMatch.group(7) ?? '';
        final String toMin = rangoMatch.group(8) ?? '00';
        final String toPeriod = (rangoMatch.group(9) ?? '').toLowerCase();
        int fromHourInt = int.tryParse(fromHour) ?? 0;
        int toHourInt = int.tryParse(toHour) ?? 0;
        if (fromPeriod.contains('tarde') ||
            fromPeriod.contains('pm') ||
            fromPeriod.contains('p.m.')) {
          if (fromHourInt < 12) fromHourInt += 12;
        }
        if (toPeriod.contains('tarde') ||
            toPeriod.contains('pm') ||
            toPeriod.contains('p.m.')) {
          if (toHourInt < 12) toHourInt += 12;
        }
        if (toPeriod.isEmpty && toHourInt < fromHourInt) {
          toHourInt += 12;
        }
        final horarioMap = <String, String>{
          'from':
              '${fromHourInt.toString().padLeft(2, '0')}:${fromMin.padLeft(2, '0')}',
          'to':
              '${toHourInt.toString().padLeft(2, '0')}:${toMin.padLeft(2, '0')}',
          'days': diasMatch != null
              ? (diasMatch.group(0)?.replaceAll(RegExp(r'\s+'), ' ').trim() ??
                    '')
              : '',
        };
        // Guardar en biography según el tipo
        try {
          final Map<String, dynamic> bio = Map<String, dynamic>.from(
            onboardingData.biography,
          );
          final dias = horarioMap['days'] ?? '';
          DateTime? computeNextForDays(final String daysStr) {
            try {
              final Map<String, int> map = {
                'lun': 1,
                'lunes': 1,
                'mar': 2,
                'martes': 2,
                'mie': 3,
                'mié': 3,
                'miercoles': 3,
                'miércoles': 3,
                'jue': 4,
                'jueves': 4,
                'vie': 5,
                'viernes': 5,
                'sab': 6,
                'sáb': 6,
                'sabado': 6,
                'sábado': 6,
                'dom': 7,
                'domingo': 7,
              };
              final dayNameRe = RegExp(r'([a-záéíóú]{3,9})');
              final m = dayNameRe.firstMatch(daysStr.toLowerCase());
              if (m == null) return null;
              final key = m.group(1)!;
              final wd = map[key];
              if (wd == null) return null;
              final now = DateTime.now();
              int delta = (wd - now.weekday);
              if (delta < 0) delta += 7;
              if (delta == 0) {
                delta = 7; // next occurrence is next week (avoid today)
              }
              return DateTime(
                now.year,
                now.month,
                now.day,
              ).add(Duration(days: delta));
            } on Exception catch (_) {
              return null;
            }
          }

          // Detectar intervalos explícitos en la cadena original (p.ej. 'cada dos semanas')
          final hasBiweekly =
              textResponse.toLowerCase().contains('cada dos semanas') ||
              textResponse.toLowerCase().contains('cada 2 semanas') ||
              textResponse.toLowerCase().contains('cada quincena');
          final hasWeekly = textResponse.toLowerCase().contains('cada semana');
          final hasMonthly = textResponse.toLowerCase().contains('cada mes');

          final entry = <String, dynamic>{
            'from': horarioMap['from'] ?? '',
            'to': horarioMap['to'] ?? '',
            if (dias.isNotEmpty) 'dias': dias,
          };
          if (hasBiweekly) {
            entry['interval'] = 2;
            final sd = computeNextForDays(dias);
            if (sd != null) entry['startDate'] = sd.toIso8601String();
          }
          if (hasWeekly) {
            entry['interval'] = 1;
          }
          if (hasMonthly) {
            entry['unit'] = 'months';
          }
          if (tipoHorario == 'sleep') {
            bio['horario_dormir'] = entry;
          } else if (tipoHorario == 'work') {
            // Por defecto guardar como horario_trabajo; (estudio se detectará aparte si aplica)
            bio['horario_trabajo'] = entry;
          } else if (tipoHorario == 'study') {
            bio['horario_estudio'] = entry;
          } else if (tipoHorario == 'busy') {
            final List<dynamic> acts = (bio['horarios_actividades'] is List)
                ? List<dynamic>.from(bio['horarios_actividades'])
                : <dynamic>[];
            acts.add(entry);
            bio['horarios_actividades'] = acts;
          }
          onboardingData = onboardingData.copyWith(biography: bio);
          await saveAll();
          Log.d(
            'Guardado en biography: $tipoHorario=$entry',
            tag: 'HORARIO_IA',
          );
        } on Exception catch (e) {
          Log.e('Error guardando en biography: $e', tag: 'HORARIO_IA');
        }
      }
    }
    return onboardingData;
  }
}
