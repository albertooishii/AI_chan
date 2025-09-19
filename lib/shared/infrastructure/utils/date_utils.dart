import 'dart:math';

/// Utilidades para manejo de fechas en la generación de biografías de IA
class DateUtils {
  /// Calcula la edad actual basada en la fecha de nacimiento
  static int calculateAge(
    final DateTime birthDate, {
    final DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    int age = now.year - birthDate.year;
    final hasHadBirthdateThisYear =
        (now.month > birthDate.month) ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hasHadBirthdateThisYear) age -= 1;
    return age;
  }

  /// Genera una fecha de nacimiento aleatoria para la IA basada en la edad del usuario
  static DateTime generateAIBirthdate(
    final DateTime? userBirthdate, {
    final int? seed,
    final DateTime? referenceDate,
  }) {
    final rng = seed != null ? Random(seed) : Random();
    final now = referenceDate ?? DateTime.now();

    final userAge = userBirthdate != null
        ? calculateAge(userBirthdate, referenceDate: referenceDate)
        : 25; // Default age if no userBirthdate provided
    final targetAge = (userAge - 2) < 18 ? 18 : (userAge - 2);
    final aiYear = now.year - targetAge;
    final aiMonth = rng.nextInt(12) + 1;
    final lastDay = DateTime(aiYear, aiMonth + 1, 0).day;
    final aiDay = rng.nextInt(lastDay) + 1;

    return DateTime(aiYear, aiMonth, aiDay);
  }

  /// Convierte una fecha DateTime a string en formato YYYY-MM-DD
  static String dateToIsoString(final DateTime date) {
    return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  /// Obtiene la fecha actual en formato YYYY-MM-DD
  static String getCurrentDateString({final DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    return dateToIsoString(now);
  }

  /// Calcula la fecha de hace un mes de forma segura
  static DateTime getDateOneMonthAgo({final DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    int prevMonth = now.month - 1;
    int prevYear = now.year;

    if (prevMonth == 0) {
      prevMonth = 12;
      prevYear -= 1;
    }

    final lastDayPrevMonth = DateTime(prevYear, prevMonth + 1, 0).day;
    final safeDay = now.day <= lastDayPrevMonth ? now.day : lastDayPrevMonth;

    return DateTime(prevYear, prevMonth, safeDay);
  }

  /// Obtiene la fecha de hace un mes en formato YYYY-MM-DD
  static String getDateOneMonthAgoString({final DateTime? referenceDate}) {
    final oneMonthAgo = getDateOneMonthAgo(referenceDate: referenceDate);
    return dateToIsoString(oneMonthAgo);
  }
}
