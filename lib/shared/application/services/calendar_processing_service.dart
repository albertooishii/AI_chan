import 'package:ai_chan/shared/utils/schedule_utils.dart';

/// Servicio para manejar la lógica de procesamiento de calendario
/// Separa el parsing y validación de horarios de la capa de presentación
class CalendarProcessingService {
  /// Procesa una cadena de horario y devuelve una especificación de horario
  static dynamic processScheduleString(final String daysString) {
    return ScheduleUtils.parseScheduleString(daysString);
  }

  /// Procesa una entrada de calendario raw con validaciones
  static Map<String, dynamic> processCalendarEntry({
    required final String daysString,
    required final DateTime day,
    final Map<String, String>? rawEntry,
  }) {
    final spec = processScheduleString(daysString);

    // Procesar datos adicionales si existen
    if (rawEntry != null) {
      final processedData = <String, dynamic>{'spec': spec, 'day': day};

      try {
        final rInterval = rawEntry['interval'];
        final rUnit = rawEntry['unit'];
        final rStart = rawEntry['startDate'];

        int? interval;
        DateTime? startDate;

        if (rInterval != null) interval = int.tryParse(rInterval);
        if (rStart != null && rStart.isNotEmpty) {
          startDate = DateTime.tryParse(rStart);
        }

        processedData['interval'] = interval;
        processedData['unit'] = rUnit;
        processedData['startDate'] = startDate;
      } catch (e) {
        // Si hay error en el parsing, devolver datos básicos
        processedData['error'] = e.toString();
      }

      return processedData;
    }

    return {'spec': spec, 'day': day};
  }

  /// Procesa una cadena de tiempo en formato HH:MM
  static DateTime? processTimeString(
    final DateTime baseDay,
    final String hhmm,
  ) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(baseDay.year, baseDay.month, baseDay.day, h, m);
  }

  /// Verifica si una fecha está dentro de un rango de tiempo
  static bool rangeContains(
    final DateTime now,
    final DateTime start,
    final DateTime end,
  ) {
    if (end.isBefore(start)) {
      // Rango cruza medianoche: end pertenece al día siguiente
      return now.isAfter(start) || now.isBefore(end);
    }
    return (now.isAfter(start) || now.isAtSameMomentAs(start)) &&
        now.isBefore(end);
  }
}
