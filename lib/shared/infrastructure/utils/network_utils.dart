import 'package:ai_chan/shared.dart';

/// Utilidades de red compartidas.
/// hasInternetConnection intenta una conexión TCP corta a un DNS público
/// para detectar conectividad básica. Devuelve true si puede conectar.
Future<bool> hasInternetConnection({
  final Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final SocketLike socket = await SocketConnector.connect(
      '8.8.8.8',
      53,
      timeout: timeout,
    );
    try {
      socket.destroy();
    } on Exception catch (_) {}
    return true;
  } on Exception catch (_) {
    return false;
  }
}
