import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/models.dart';
import '../utils/event_parser_utils.dart';
// event_entry is exported by core barrel

class EventTimelineService {
  // Añade un evento al timeline si se detecta fecha y palabras clave
  static TimelineEntry? createEventFromText(String text) {
    final date = EventParserUtils.parseFullDate(text);
    if (date != null && EventParserUtils.containsEventKeywords(text)) {
      // Extraer la frase más larga y significativa del texto
      final frases = text.split(RegExp(r'[\.\n!?]')).map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
      // Elegir la frase más larga (probablemente el nombre del evento)
      String descripcionEvento = frases.isNotEmpty ? frases.reduce((a, b) => a.length >= b.length ? a : b) : 'Evento';
      // Limpiar markdown y caracteres especiales
      descripcionEvento = descripcionEvento.replaceAll(RegExp(r'\*|\_|\#|\-|\`|\>|\[|\]|\(|\)|\:|\;'), '').trim();
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
        dateWithHour = DateTime(date.year, date.month, date.day, hour, minute, 0);
      }
      final startDate = dateWithHour.toIso8601String();
      return TimelineEntry(resume: descripcionEvento, startDate: startDate, level: 1);
    }
    return null;
  }

  /// Detecta y guarda automáticamente eventos/citas y horarios en el perfil
  static Future<dynamic> detectAndSaveEventAndSchedule({
    required String text,
    required String textResponse,
    required dynamic onboardingData,
    required Future<void> Function() saveAll,
  }) async {
    // --- EVENTOS/CITAS ---
    final eventEntry = createEventFromText(textResponse);
    if (eventEntry != null) {
      // Convertir TimelineEntry a EventEntry y guardar en events
      List<EventEntry> updatedEvents = onboardingData.events != null
          ? List<EventEntry>.from(onboardingData.events)
          : <EventEntry>[];
      // Usar la frase significativa extraída por createEventFromText
      final descripcionNatural = eventEntry.resume;
      final DateTime? eventDate = (eventEntry.startDate != null && eventEntry.startDate != '')
          ? DateTime.parse(eventEntry.startDate!)
          : null;
      bool isDuplicate = false;
      for (final ev in updatedEvents) {
        final sameDesc = ev.description.trim().toLowerCase() == descripcionNatural.trim().toLowerCase();
        final sameDay =
            ev.date != null &&
            eventDate != null &&
            ev.date!.year == eventDate.year &&
            ev.date!.month == eventDate.month &&
            ev.date!.day == eventDate.day;
        final closeInTime =
            ev.date != null && eventDate != null && (ev.date!.difference(eventDate).inMinutes).abs() <= 120;
        if (ev.type == 'evento' && sameDesc && (sameDay || closeInTime)) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        updatedEvents.add(EventEntry(type: 'evento', description: descripcionNatural, date: eventDate));
        onboardingData = onboardingData.copyWith(events: updatedEvents);
        await saveAll();
        debugPrint('[EVENTO IA] Guardado evento en events: $descripcionNatural (${eventEntry.startDate})');
      } else {
        debugPrint(
          '[EVENTO IA] Evento duplicado detectado. No se guarda: $descripcionNatural (${eventEntry.startDate})',
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
    final sleepWords = r'sueño|dormir|duermo|duerma|duermes|duerme|duermen|dormido|dormida|dormidas|dormidos|sleep';
    final workWords = r'trabajo|work';
    final busyWords =
        r'ocupada|ocupación|busy|gimnasio|gym|compras|reunión|reunion|cita|viaje|deporte|actividad|evento|tarea|proyecto';
    final studyWords =
        r'estudio|estudiar|clase|universidad|escuela|facultad|tutoría|tutoria|asignatura|examen|prácticas|practicas';
    final preguntaSleep = text.contains(RegExp(sleepWords, caseSensitive: false));
    final respuestaSleep = textResponse.contains(RegExp(sleepWords, caseSensitive: false));
    final respuestaWork = textResponse.contains(RegExp(workWords, caseSensitive: false));
    final respuestaBusy = textResponse.contains(RegExp(busyWords, caseSensitive: false));
    final diasMatch = diasRegex.firstMatch(textResponse);
    final rangoMatch = rangoRegex.firstMatch(textResponse);
    if (!regexVagoCheck.hasMatch(textResponse) && rangoMatch != null) {
      String tipoHorario = '';
      if (respuestaSleep) {
        tipoHorario = 'sleep';
      } else if (respuestaWork) {
        tipoHorario = 'work';
      } else if (textResponse.contains(RegExp(studyWords, caseSensitive: false))) {
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
      debugPrint('[HORARIO IA] Intentando extraer días: ${diasMatch != null ? diasMatch.group(0) : 'NO DETECTADO'}');
      debugPrint('[HORARIO IA] Intentando extraer rango de horas: ${rangoMatch.group(0)}');
      if (tipoHorario.isNotEmpty) {
        String fromHour = rangoMatch.group(2) ?? '';
        String fromMin = rangoMatch.group(3) ?? '00';
        String fromPeriod = (rangoMatch.group(4) ?? '').toLowerCase();
        String toHour = rangoMatch.group(7) ?? '';
        String toMin = rangoMatch.group(8) ?? '00';
        String toPeriod = (rangoMatch.group(9) ?? '').toLowerCase();
        int fromHourInt = int.tryParse(fromHour) ?? 0;
        int toHourInt = int.tryParse(toHour) ?? 0;
        if (fromPeriod.contains('tarde') || fromPeriod.contains('pm') || fromPeriod.contains('p.m.')) {
          if (fromHourInt < 12) fromHourInt += 12;
        }
        if (toPeriod.contains('tarde') || toPeriod.contains('pm') || toPeriod.contains('p.m.')) {
          if (toHourInt < 12) toHourInt += 12;
        }
        if (toPeriod.isEmpty && toHourInt < fromHourInt) {
          toHourInt += 12;
        }
        final horarioMap = <String, String>{
          'from': '${fromHourInt.toString().padLeft(2, '0')}:${fromMin.padLeft(2, '0')}',
          'to': '${toHourInt.toString().padLeft(2, '0')}:${toMin.padLeft(2, '0')}',
          'days': diasMatch != null ? (diasMatch.group(0)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '') : '',
        };
        // Guardar en biography según el tipo
        try {
          final Map<String, dynamic> bio = Map<String, dynamic>.from(onboardingData.biography);
          final dias = horarioMap['days'] ?? '';
          final entry = {
            'from': horarioMap['from'] ?? '',
            'to': horarioMap['to'] ?? '',
            if (dias.isNotEmpty) 'dias': dias,
          };
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
          debugPrint('[HORARIO IA] Guardado en biography: $tipoHorario=$entry');
        } catch (e) {
          debugPrint('[HORARIO IA] Error guardando en biography: $e');
        }
      }
    }
    return onboardingData;
  }
}
