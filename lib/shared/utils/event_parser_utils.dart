class EventParserUtils {
  // Detecta fechas completas en texto tipo "sábado 9 de agosto de 2025"
  static DateTime? parseFullDate(String text) {
    final dateRegex = RegExp(
      r'(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)?\s*(\d{1,2})\s*de\s*(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\s*de\s*(\d{4})',
      caseSensitive: false,
    );
    final match = dateRegex.firstMatch(text);
    if (match != null) {
      final day = int.tryParse(match.group(2) ?? '1') ?? 1;
      final monthStr = match.group(3)?.toLowerCase() ?? '';
      final year = int.tryParse(match.group(4) ?? '') ?? DateTime.now().year;
      final months = {
        'enero': 1,
        'febrero': 2,
        'marzo': 3,
        'abril': 4,
        'mayo': 5,
        'junio': 6,
        'julio': 7,
        'agosto': 8,
        'septiembre': 9,
        'octubre': 10,
        'noviembre': 11,
        'diciembre': 12,
      };
      final month = months[monthStr] ?? DateTime.now().month;
      return DateTime(year, month, day);
    }
    return null;
  }

  // Detecta palabras clave de evento/cita
  static bool containsEventKeywords(String text) {
    final keywords = [
      'cita',
      'evento',
      'festival',
      'concierto',
      'cumpleaños',
      'aniversario',
      'reunión',
      'reunion',
      'fiesta',
      'quedada',
      'salida',
      'plan',
      'celebración',
      'celebracion',
      'boda',
      'viaje',
      'excursión',
      'excursion',
      'feria',
      'exposición',
      'exposicion',
      'ceremonia',
      'party',
      'meet',
      'date',
      'appointment',
      'gala',
      'picnic',
      'fireworks',
      'fuegos artificiales',
    ];
    return keywords.any((kw) => text.toLowerCase().contains(kw));
  }
}
