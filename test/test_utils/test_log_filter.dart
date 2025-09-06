/// Filtro de logs para tests - reduce ruido sin afectar validación
library;

class TestLogFilter {
  static bool _filterEnabled = false;
  static final List<String> _noisyPatterns = [
    'MissingPluginException(No implementation found for method getTemporaryDirectory',
    'MissingPluginException(No implementation found for method getApplicationDocumentsDirectory',
    'MissingPluginException(No implementation found for method getApplicationSupportDirectory',
    'ImageException: Invalid IDAT checksum',
    'Error decodificando imagen, intentando guardar como está',
    'Binding has not yet been initialized',
    'Error starting ringback: MissingPluginException',
  ];

  /// Habilita filtrado de logs durante tests
  static void enableForTests() {
    _filterEnabled = true;
  }

  /// Deshabilita filtrado (para debug específico)
  static void disable() {
    _filterEnabled = false;
  }

  /// Verifica si un mensaje debe ser suprimido
  static bool shouldSuppressMessage(final String message) {
    if (!_filterEnabled) return false;

    for (final pattern in _noisyPatterns) {
      if (message.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  /// Wrapper para tests que genera mucho ruido
  static T withQuietLogging<T>(final T Function() testFunction) {
    final wasEnabled = _filterEnabled;
    enableForTests();
    try {
      return testFunction();
    } finally {
      if (!wasEnabled) disable();
    }
  }

  /// Para tests específicos que necesitan logs completos
  static T withFullLogging<T>(final T Function() testFunction) {
    final wasEnabled = _filterEnabled;
    disable();
    try {
      return testFunction();
    } finally {
      if (wasEnabled) enableForTests();
    }
  }
}
