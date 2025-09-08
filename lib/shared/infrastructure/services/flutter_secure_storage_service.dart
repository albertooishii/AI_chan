import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ai_chan/chat/domain/interfaces/i_secure_storage_service.dart';

/// Real implementation of ISecureStorageService using FlutterSecureStorage
/// Provides secure storage for sensitive data like credentials
class FlutterSecureStorageService implements ISecureStorageService {
  const FlutterSecureStorageService();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(final String key) async {
    try {
      return await _storage.read(key: key);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(final String key, final String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Exception {
      // Silently fail - non-critical operation
    }
  }

  @override
  Future<void> delete(final String key) async {
    try {
      await _storage.delete(key: key);
    } on Exception {
      // Silently fail - non-critical operation
    }
  }

  @override
  Future<bool> containsKey(final String key) async {
    try {
      return await _storage.containsKey(key: key);
    } on Exception {
      return false;
    }
  }
}
