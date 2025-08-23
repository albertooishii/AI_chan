import 'package:ai_chan/core/di_bootstrap.dart' as boot;

/// Test helper: registra las fábricas por defecto (mismo wiring que en app)
/// y permite resetear el factory registry si es necesario desde pruebas.
void registerDefaultRealtimeFactoriesForTest() {
  // Reuse the same bootstrap wiring so unit tests and integration tests
  // share the same defaults.
  boot.registerDefaultRealtimeClientFactories();
}

/// Nota: si necesitas resetear el registro entre tests, usa
/// `setTestRealtimeClientFactory` o reinicia el proceso de test.
