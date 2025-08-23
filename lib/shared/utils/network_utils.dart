import 'dart:io';

/// Utilidades de red compartidas.
/// hasInternetConnection intenta una conexión TCP corta a un DNS público
/// para detectar conectividad básica. Devuelve true si puede conectar.
Future<bool> hasInternetConnection({Duration timeout = const Duration(seconds: 2)}) async {
  try {
    final socket = await Socket.connect('8.8.8.8', 53, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
