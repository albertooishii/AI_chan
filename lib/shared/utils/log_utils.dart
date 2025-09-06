import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/config.dart';
import 'dart:developer' as dev;

/// Niveles de log soportados (cuanto mayor el número, más detallado)
/// error(0) < warn(1) < info(2) < debug(3) < trace(4)
enum LogLevel { error, warn, info, debug, trace }

class Log {
  // DEBUG_MODE controla tanto el nivel de log como otras opciones de debug
  static LogLevel get _configuredLevel {
    String? raw;
    try {
      raw = Config.get('DEBUG_MODE', '').toLowerCase().trim();
      if (raw.isEmpty) raw = null;
    } on Exception catch (_) {
      raw = null;
    }
    switch (raw) {
      case 'full':
        return LogLevel.debug;
      case 'basic':
        return LogLevel
            .debug; // Cambiado de info a debug para mostrar logs de debug
      case 'minimal':
        return LogLevel.warn;
      case 'off':
        return LogLevel.error;
      default:
        // Si no se define: en debug -> debug, en release -> warn
        return kDebugMode ? LogLevel.debug : LogLevel.warn;
    }
  }

  static int _levelIndex(final LogLevel l) => l.index; // ordinal

  static bool _enabledFor(final LogLevel level) {
    // Siempre permitir errores (aunque se esté en producción)
    final configured = _configuredLevel;
    return _levelIndex(level) <= _levelIndex(configured);
  }

  // Helper para que otros módulos puedan consultar el modo debug
  static String get debugMode {
    try {
      return Config.get('DEBUG_MODE', '').toLowerCase().trim();
    } on Exception catch (_) {
      return kDebugMode ? 'full' : 'basic';
    }
  }

  // Helper para verificar si las opciones de debug deben mostrarse en UI
  static bool get showDebugOptions {
    final mode = debugMode;
    return mode != 'off';
  }

  static void _out(
    final LogLevel level,
    final String tag,
    final String message,
  ) {
    if (!_enabledFor(level)) return;

    // Colores ANSI para diferentes niveles
    String colorCode = '';
    String emoji = '';
    switch (level) {
      case LogLevel.error:
        colorCode = '\x1B[91m'; // Rojo brillante
        emoji = '❌';
        break;
      case LogLevel.warn:
        colorCode = '\x1B[93m'; // Amarillo brillante
        emoji = '⚠️';
        break;
      case LogLevel.info:
        colorCode = '\x1B[94m'; // Azul brillante
        emoji = 'ℹ️';
        break;
      case LogLevel.debug:
        colorCode = '\x1B[95m'; // Magenta brillante
        emoji = '🔍';
        break;
      case LogLevel.trace:
        colorCode = '\x1B[90m'; // Gris
        emoji = '📍';
        break;
    }
    const reset = '\x1B[0m';

    final levelStr = level.name.toUpperCase();
    final coloredLine = '$colorCode$emoji [$levelStr][$tag] $message$reset';

    // En modo debug preferimos debugPrint (con colores) para consola.
    // Evitar llamar a dart:developer.log en debug porque muchas herramientas
    // muestran ambos (dev.log + stdout) y provoca líneas duplicadas.
    if (!kDebugMode) {
      // dart:developer.log para herramientas de desarrollo/entornos no-debug
      dev.log(message, name: '$emoji $tag', level: _levelIndex(level));
    }

    // debugPrint con colores para consola en modo debug
    if (kDebugMode) {
      debugPrint(coloredLine);
    }
  }

  // Helpers principales
  static void e(
    final String message, {
    final String tag = 'APP',
    final Object? error,
    final StackTrace? stack,
  }) {
    final msg = error != null ? '$message | error=$error' : message;
    _out(LogLevel.error, tag, msg + (stack != null ? '\n$stack' : ''));
  }

  static void w(final String message, {final String tag = 'APP'}) =>
      _out(LogLevel.warn, tag, message);
  static void i(final String message, {final String tag = 'APP'}) =>
      _out(LogLevel.info, tag, message);
  static void d(final String message, {final String tag = 'APP'}) =>
      _out(LogLevel.debug, tag, message);
}
