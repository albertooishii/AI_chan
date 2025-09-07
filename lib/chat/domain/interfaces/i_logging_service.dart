/// Logging Service - Domain Port
/// Interfaz para servicios de logging y monitoreo.
/// Abstrae la funcionalidad de logging para diferentes niveles y contextos.
abstract class ILoggingService {
  /// Log de nivel DEBUG.
  void debug(final String message, {final String? tag, final Object? error});

  /// Log de nivel INFO.
  void info(final String message, {final String? tag, final Object? error});

  /// Log de nivel WARNING.
  void warning(final String message, {final String? tag, final Object? error});

  /// Log de nivel ERROR.
  void error(
    final String message, {
    final String? tag,
    final Object? error,
    final StackTrace? stackTrace,
  });
}
