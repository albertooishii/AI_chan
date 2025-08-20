class ScheduleUtils {
  static int? parseHmToMinutes(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// Devuelve true si currentMinutes (minutos desde 00:00) cae dentro del rango [from, to),
  /// donde from y to son cadenas HH:mm. Maneja rangos que cruzan medianoche.
  /// Si el rango es inválido, devuelve null.
  static bool? isTimeInRange({required int currentMinutes, required String from, required String to}) {
    if (from.isEmpty || to.isEmpty) return null;
    final int? fm = parseHmToMinutes(from);
    final int? tm = parseHmToMinutes(to);
    if (fm == null || tm == null) return null;
    if (tm <= fm) {
      // Cruza medianoche: válido desde fm..1440 y 0..tm
      return currentMinutes >= fm || currentMinutes < tm;
    }
    // Rango normal [fm, tm)
    return currentMinutes >= fm && currentMinutes < tm;
  }

  static Set<int>? parseDiasToWeekdaySet(String dias) {
    final d = dias.trim().toLowerCase();
    if (d.isEmpty) return null; // null => aplica todos los días
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
    for (final p in d.split(',')) {
      final key = p.trim();
      if (key.isEmpty) continue;
      if (map.containsKey(key)) out.add(map[key]!);
    }
    if (out.isEmpty) return null;
    return out;
  }
}
