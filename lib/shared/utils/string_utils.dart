/// Normaliza strings removiendo acentos y convirtiendo a minúsculas para búsquedas
///
/// Ejemplo:
/// ```dart
/// normalizeForSearch("José María") // -> "jose maria"
/// ```
String normalizeForSearch(final String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');
}

/// Normaliza strings removiendo solo acentos (sin cambiar a minúsculas)
///
/// Ejemplo:
/// ```dart
/// removeAccents("José María") // -> "Jose Maria"
/// ```
String removeAccents(final String text) {
  return text
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll(RegExp('[ÁÀÄÂÃ]'), 'A')
      .replaceAll(RegExp('[ÉÈËÊ]'), 'E')
      .replaceAll(RegExp('[ÍÌÏÎ]'), 'I')
      .replaceAll(RegExp('[ÓÒÖÔÕ]'), 'O')
      .replaceAll(RegExp('[ÚÙÜÛ]'), 'U')
      .replaceAll('ñ', 'n')
      .replaceAll('Ñ', 'N')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C');
}

/// Normaliza transcripciones removiendo puntuación y espacios extras
///
/// Ejemplo:
/// ```dart
/// normalizeTranscription("¡Hola, mundo!  ") // -> "hola mundo"
/// ```
String normalizeTranscription(final String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '') // Remover puntuación
      .replaceAll(RegExp(r'\s+'), ' ') // Normalizar espacios
      .trim();
}

/// Limpia texto para subtítulos (normaliza espacios y signos de puntuación)
///
/// Ejemplo:
/// ```dart
/// cleanSubtitleText("¡  Hola    mundo!") // -> "¡Hola mundo!"
/// ```
String cleanSubtitleText(final String text) {
  var cleaned = text.trim();
  if (cleaned.isEmpty) return '';

  // Normalizar múltiples espacios a uno solo
  cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ');

  // Pegar signos de apertura con la siguiente palabra
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'([¡¿])\s+([A-Za-zÁÉÍÓÚáéíóúÑñ])'),
    (final m) => '${m.group(1)}${m.group(2)}',
  );

  return cleaned;
}
