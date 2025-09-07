import 'package:ai_chan/chat/domain/interfaces/i_secure_storage_service.dart';

/// Basic implementation of ISecureStorageService for dependency injection
class BasicSecureStorageService implements ISecureStorageService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(final String key) async {
    return _storage[key];
  }

  @override
  Future<void> write(final String key, final String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete(final String key) async {
    _storage.remove(key);
  }

  @override
  Future<bool> containsKey(final String key) async {
    return _storage.containsKey(key);
  }
}
