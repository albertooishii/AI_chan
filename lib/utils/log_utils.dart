import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as dev;

/// Niveles de log soportados (cuanto mayor el número, más detallado)
/// error(0) < warn(1) < info(2) < debug(3) < trace(4)
enum LogLevel { error, warn, info, debug, trace }

class Log {
  // Solo APP_LOG_LEVEL controla el nivel de log. APP_DEBUG_LOGS ya no tiene efecto.
  static LogLevel get _configuredLevel {
    final raw = dotenv.env['APP_LOG_LEVEL']?.toLowerCase().trim();
    switch (raw) {
      case 'error':
        return LogLevel.error;
      case 'warn':
      case 'warning':
        return LogLevel.warn;
      case 'info':
        return LogLevel.info;
      case 'trace':
        return LogLevel.trace;
      case 'debug':
        return LogLevel.debug;
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

  static void _out(LogLevel level, String tag, String message) {
    if (!_enabledFor(level)) return;
    final levelStr = level.name.toUpperCase();
    final line = '[$levelStr][$tag] $message';
    // dart:developer.log permite tooling
    dev.log(line, name: tag, level: _levelIndex(level));
    // fallback visible en consola
    debugPrint(line); // fallback de consola, no migrar
    // (métodos estáticos incorrectos eliminados)
    // Métodos alternativos para compatibilidad con migración
  }

  // Helpers principales
  static void e(String message, {String tag = 'APP', Object? error, StackTrace? stack}) {
    final msg = error != null ? '$message | error=$error' : message;
    _out(LogLevel.error, tag, msg + (stack != null ? '\n$stack' : ''));
  }

  static void w(String message, {String tag = 'APP'}) => _out(LogLevel.warn, tag, message);
  static void i(String message, {String tag = 'APP'}) => _out(LogLevel.info, tag, message);
  static void d(String message, {String tag = 'APP'}) => _out(LogLevel.debug, tag, message);
  static void t(String message, {String tag = 'APP'}) => _out(LogLevel.trace, tag, message);

  // Versiones lazy para evitar construir strings costosas
  static void dLazy(String Function() builder, {String tag = 'APP'}) {
    if (_enabledFor(LogLevel.debug)) _out(LogLevel.debug, tag, builder());
  }

  static void tLazy(String Function() builder, {String tag = 'APP'}) {
    if (_enabledFor(LogLevel.trace)) _out(LogLevel.trace, tag, builder());
  }

  // Registro de excepción estándar
  static void ex(Object error, StackTrace stack, {String tag = 'APP', String? context}) {
    e(context ?? 'Excepción capturada', tag: tag, error: error, stack: stack);
  }
}
