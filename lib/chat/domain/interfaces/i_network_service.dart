/// Network Service - Domain Port
/// Interfaz para servicios de conectividad de red.
/// Abstrae la verificación de conectividad a internet.
abstract class INetworkService {
  /// Verifica si hay conexión a internet.
  Future<bool> hasInternetConnection();
}
