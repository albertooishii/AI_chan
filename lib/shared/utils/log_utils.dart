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
    } catch (_) {
      raw = null;
    }
    switch (raw) {
      case 'full':
        return LogLevel.debug;
      case 'basic':
        return LogLevel.info;
      case 'minimal':
        return LogLevel.warn;
      case 'off':
        return LogLevel.error;
      default:
        // Si no se define: en debug -> debug, en release -> warn
        return kDebugMode ? LogLevel.debug : LogLevel.warn;
    }
  }

  static int _levelIndex(LogLevel l) => l.index; // ordinal

  static bool _enabledFor(LogLevel level) {
    // Siempre permitir errores (aunque se esté en producción)
    final configured = _configuredLevel;
    return _levelIndex(level) <= _levelIndex(configured);
  }

  // Helper para que otros módulos puedan consultar el modo debug
  static String get debugMode {
    try {
      return Config.get('DEBUG_MODE', '').toLowerCase().trim();
    } catch (_) {
      return kDebugMode ? 'full' : 'basic';
    }
  }

  // Helper para verificar si las opciones de debug deben mostrarse en UI
  static bool get showDebugOptions {
    final mode = debugMode;
    return mode != 'off';
  }

  static void _out(LogLevel level, String tag, String message) {
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
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stack,
  }) {
    final msg = error != null ? '$message | error=$error' : message;
    _out(LogLevel.error, tag, msg + (stack != null ? '\n$stack' : ''));
  }

  static void w(String message, {String tag = 'APP'}) =>
      _out(LogLevel.warn, tag, message);
  static void i(String message, {String tag = 'APP'}) =>
      _out(LogLevel.info, tag, message);
  static void d(String message, {String tag = 'APP'}) =>
      _out(LogLevel.debug, tag, message);
  static void t(String message, {String tag = 'APP'}) =>
      _out(LogLevel.trace, tag, message);

  // Versiones lazy para evitar construir strings costosas
  static void dLazy(String Function() builder, {String tag = 'APP'}) {
    if (_enabledFor(LogLevel.debug)) _out(LogLevel.debug, tag, builder());
  }

  static void tLazy(String Function() builder, {String tag = 'APP'}) {
    if (_enabledFor(LogLevel.trace)) _out(LogLevel.trace, tag, builder());
  }

  // Registro de excepción estándar
  static void ex(
    Object error,
    StackTrace stack, {
    String tag = 'APP',
    String? context,
  }) {
    e(context ?? 'Excepción capturada', tag: tag, error: error, stack: stack);
  }
}
