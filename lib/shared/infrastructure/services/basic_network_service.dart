import 'package:ai_chan/chat/domain/interfaces/i_network_service.dart';

/// Basic implementation of INetworkService for dependency injection
class BasicNetworkService implements INetworkService {
  @override
  Future<bool> hasInternetConnection() async {
    // Basic implementation assumes internet is always available
    return true;
  }
}
