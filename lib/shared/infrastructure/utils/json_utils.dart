import 'dart:convert';

/// Extrae el primer bloque JSON válido de un texto, limpiando caracteres extra.
/// Si no encuentra un bloque válido, retorna {'raw': texto}.
Map<String, dynamic> extractJsonBlock(final String text) {
  final String cleaned = text.trim();
  final startIdx = cleaned.indexOf('{');
  final endIdx = cleaned.lastIndexOf('}');
  if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
    final jsonStr = cleaned.substring(startIdx, endIdx + 1);
    final jsonClean = jsonStr.replaceAll(RegExp(r'^[^\{]*|[^\}]*$'), '');
    try {
      final decoded = jsonDecode(jsonClean);
      // Si el resultado es un string (posible JSON anidado), intenta decodificar de nuevo
      if (decoded is String) {
        try {
          return jsonDecode(decoded);
        } on Exception catch (_) {
          return {'raw': decoded};
        }
      }
      return decoded;
    } on Exception catch (_) {
      return {'raw': jsonClean};
    }
  } else {
    return {'raw': cleaned};
  }
}
