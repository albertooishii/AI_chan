import 'package:ai_chan/shared/utils/log_utils.dart';

/// Helper para detectar errores de inicialización del runtime (dotenv, keys faltantes)
/// Devuelve true si el error corresponde a un problema de configuración/local (no inicializado o falta de API key).
bool handleRuntimeError(Object err, String context) {
  final msg = err.toString();
  if (msg.contains('NotInitializedError') ||
      msg.contains('Falta la API key') ||
      msg.contains('Missing') ||
      msg.contains('dotenv')) {
    Log.w('[$context] Falló por configuración/local (no initialized): $msg');
    return true;
  }
  return false;
}
