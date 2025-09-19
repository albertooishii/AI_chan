/// Pure domain utilities for schedule and time calculations
/// This class contains pure functions without external dependencies
class ScheduleUtils {
  static int? parseHmToMinutes(final String s) {
    final parts = s.split(':');
    if (parts.length != 2) {
      return null;
    }
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) {
      return null;
    }
    if (h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }

  /// Devuelve true si currentMinutes (minutos desde 00:00) cae dentro del rango [from, to),
  /// donde from y to son cadenas HH:mm. Maneja rangos que cruzan medianoche.
  /// Si el rango es inválido, devuelve null.
  static bool? isTimeInRange({
    required final int currentMinutes,
    required final String from,
    required final String to,
  }) {
    if (from.isEmpty || to.isEmpty) {
      return null;
    }
    final int? fm = parseHmToMinutes(from);
    final int? tm = parseHmToMinutes(to);
    if (fm == null || tm == null) {
      return null;
    }
    if (tm <= fm) {
      // Cruza medianoche: válido desde fm..1440 y 0..tm
      return currentMinutes >= fm || currentMinutes < tm;
    }
    // Rango normal [fm, tm)
    return currentMinutes >= fm && currentMinutes < tm;
  }

  static Set<int>? parseDiasToWeekdaySet(final String dias) {
    final d = dias.trim().toLowerCase();
    if (d.isEmpty) {
      return null; // null => aplica todos los días
    }
    final map = <String, int>{
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
    final out = <int>{};
    final range = RegExp(r'([a-záéíóú]{3,9})\s*-\s*([a-záéíóú]{3,9})');
    final rangeMatch = range.firstMatch(d);
    if (rangeMatch != null) {
      final start = map[rangeMatch.group(1)!];
      final end = map[rangeMatch.group(2)!];
      if (start != null && end != null) {
        int i = start;
        while (true) {
          out.add(i);
          if (i == end) break;
          i = i % 7 + 1;
        }
      }
    }
    // Cada fragmento puede incluir calificadores como "(cada dos semanas)" o "cada 2 semanas".
    // Extraemos la primera palabra que parezca un día y la usamos.
    final dayNameRe = RegExp(r'([a-záéíóú]{3,9})');
    for (final p in d.split(',')) {
      final raw = p.trim();
      if (raw.isEmpty) {
        continue;
      }
      final m = dayNameRe.firstMatch(raw);
      if (m != null) {
        final key = m.group(1)!.trim();
        if (map.containsKey(key)) {
          out.add(map[key]!);
        }
      }
    }
    if (out.isEmpty) {
      return null;
    }
    return out;
  }

  // Especificación de schedule más completa
  // days: set de weekdays (1..7), interval: número (ej. 2 para cada 2 semanas),
  // unit: 'weeks'|'months'|'days', startDate: fecha base para calcular paridad
  static ScheduleSpec parseScheduleString(final String raw) {
    final s = raw.trim();
    final days = parseDiasToWeekdaySet(s);
    int? interval;
    String? unit;
    DateTime? startDate;

    // Detectar patrones "cada X semanas/meses/días"
    final wordToNum = <String, int>{
      'uno': 1,
      'dos': 2,
      'tres': 3,
      'cuatro': 4,
      'cinco': 5,
    };
    final re = RegExp(
      r'cada\s+(\d+|uno|dos|tres|cuatro|cinco)\s*(semanas|semana|meses|mes|d[ií]as|dias)?',
      caseSensitive: false,
    );
    final m = re.firstMatch(s);
    if (m != null) {
      final numStr = m.group(1) ?? '';
      final unitStr = (m.group(2) ?? '').toLowerCase();
      int n = int.tryParse(numStr) ?? (wordToNum[numStr.toLowerCase()] ?? 0);
      if (n <= 0) {
        n = 1;
      }
      interval = n;
      if (unitStr.contains('semana')) {
        unit = 'weeks';
      } else if (unitStr.contains('mes')) {
        unit = 'months';
      } else if (unitStr.contains('d') || unitStr.contains('día')) {
        unit = 'days';
      } else {
        unit = 'weeks';
      }
    }

    // Buscar una fecha base explícita 'a partir de 2025-09-02' o 'desde 02/09/2025'
    final reIso = RegExp(
      r'(?:a partir de|desde)\s*(\d{4}-\d{2}-\d{2})',
      caseSensitive: false,
    );
    final m2 = reIso.firstMatch(s);
    if (m2 != null) {
      try {
        startDate = DateTime.parse(m2.group(1)!);
      } on Exception catch (_) {}
    } else {
      // formato dd/mm/yyyy
      final re2 = RegExp(
        r'(?:a partir de|desde)\s*(\d{1,2})/(\d{1,2})/(\d{4})',
        caseSensitive: false,
      );
      final m3 = re2.firstMatch(s);
      if (m3 != null) {
        try {
          final d = int.parse(m3.group(1)!);
          final mm = int.parse(m3.group(2)!);
          final y = int.parse(m3.group(3)!);
          startDate = DateTime(y, mm, d);
        } on Exception catch (_) {}
      }
    }

    return ScheduleSpec(
      days: days,
      interval: interval,
      unit: unit,
      startDate: startDate,
    );
  }

  static bool matchesDateWithInterval(
    final DateTime date,
    final ScheduleSpec spec,
  ) {
    // Si no hay days especificados, aplica siempre
    if (spec.days == null) return true;
    if (!spec.days!.contains(date.weekday)) return false;
    if (spec.interval == null || spec.interval == 1) {
      return true;
    }
    final start = spec.startDate ?? DateTime.now();
    if (spec.unit == null || spec.unit == 'weeks') {
      // contar semanas entre start y date (usar lunes como inicio no necesario, usar diferencia en días /7)
      final base = DateTime(start.year, start.month, start.day);
      final target = DateTime(date.year, date.month, date.day);
      final daysDiff = target.difference(base).inDays;
      final weeks = (daysDiff / 7).floor();
      return (weeks % spec.interval!) == 0;
    } else if (spec.unit == 'months') {
      final monthsDiff =
          (date.year - start.year) * 12 + (date.month - start.month);
      return (monthsDiff % spec.interval!) == 0;
    } else if (spec.unit == 'days') {
      final daysDiff = date.difference(start).inDays;
      return (daysDiff % spec.interval!) == 0;
    }
    return true;
  }
}

class ScheduleSpec {
  const ScheduleSpec({this.days, this.interval, this.unit, this.startDate});
  final Set<int>? days;
  final int? interval;
  final String? unit;
  final DateTime? startDate;
}
