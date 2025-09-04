import 'dart:math';

/// Servicio para utilidades de procesamiento de texto cyberpunk
/// Maneja la detección de puntuación y caracteres especiales para animaciones
class CyberpunkTextProcessorService {
  static final RegExp _punctOrSpace = RegExp(r'[\s.,;:!?¡¿"()\[\]{}...-]');
  static final _rand = Random();

  // Caracteres katakana para el efecto de scramble
  static const List<String> _katakana = [
    'ア',
    'イ',
    'ウ',
    'エ',
    'オ',
    'カ',
    'キ',
    'ク',
    'ケ',
    'コ',
    'サ',
    'シ',
    'ス',
    'セ',
    'ソ',
    'タ',
    'チ',
    'ツ',
    'テ',
    'ト',
    'ナ',
    'ニ',
    'ヌ',
    'ネ',
    'ノ',
    'ハ',
    'ヒ',
    'フ',
    'ヘ',
    'ホ',
    'マ',
    'ミ',
    'ム',
    'メ',
    'モ',
    'ヤ',
    'ユ',
    'ヨ',
    'ラ',
    'リ',
    'ル',
    'レ',
    'ロ',
    'ワ',
    'ヲ',
    'ン',
  ];

  // Consonantes y vocales para fallbacks
  static const List<String> _vowels = ['ア', 'エ', 'イ', 'オ', 'ウ'];

  /// Verifica si un caracter es puntuación o espacio
  static bool isPunctuationOrSpace(String char) {
    return _punctOrSpace.hasMatch(char);
  }

  /// Genera un caracter katakana aleatorio para el efecto scramble
  static String randomKatakanaChar() {
    return _katakana[_rand.nextInt(_katakana.length)];
  }

  /// Verifica si un texto contiene puntuación o espacios
  static bool containsPunctuationOrSpace(String text) {
    return _punctOrSpace.hasMatch(text);
  }

  /// Genera un caracter aleatorio de una lista de códigos de caracter
  static String randomCharFromCodes(List<int> codes) {
    return String.fromCharCode(codes[_rand.nextInt(codes.length)]);
  }

  /// Genera una vocal katakana aleatoria
  static String randomVowel() {
    return _vowels[_rand.nextInt(_vowels.length)];
  }

  /// Genera un número aleatorio para probabilidades (0.0 a 1.0)
  static double randomProbability() {
    return _rand.nextDouble();
  }
}
