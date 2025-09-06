/// Fake SharedPreferences for testing storage operations
class FakeSharedPreferences {
  static final Map<String, dynamic> _storage = <String, dynamic>{};

  static void clear() {
    _storage.clear();
  }

  static void setInitialValues(final Map<String, dynamic> values) {
    _storage.clear();
    _storage.addAll(values);
  }

  static Future<bool> setString(final String key, final String value) async {
    _storage[key] = value;
    return true;
  }

  static String? getString(final String key) {
    return _storage[key] as String?;
  }

  static Future<bool> setBool(final String key, final bool value) async {
    _storage[key] = value;
    return true;
  }

  static bool? getBool(final String key) {
    return _storage[key] as bool?;
  }

  static Future<bool> setInt(final String key, final int value) async {
    _storage[key] = value;
    return true;
  }

  static int? getInt(final String key) {
    return _storage[key] as int?;
  }

  static Future<bool> remove(final String key) async {
    _storage.remove(key);
    return true;
  }

  static Set<String> getKeys() {
    return _storage.keys.toSet();
  }
}

/// Fake Cache Service for testing caching operations
class FakeCacheService {
  static final Map<String, dynamic> _cache = <String, dynamic>{};
  static final Map<String, DateTime> _expiry = <String, DateTime>{};

  static void clear() {
    _cache.clear();
    _expiry.clear();
  }

  static Future<void> set(
    final String key,
    final dynamic value, {
    final Duration? ttl,
  }) async {
    _cache[key] = value;
    if (ttl != null) {
      _expiry[key] = DateTime.now().add(ttl);
    }
  }

  static T? get<T>(final String key) {
    // Check if expired
    if (_expiry.containsKey(key)) {
      if (DateTime.now().isAfter(_expiry[key]!)) {
        _cache.remove(key);
        _expiry.remove(key);
        return null;
      }
    }
    return _cache[key] as T?;
  }

  static Future<void> remove(final String key) async {
    _cache.remove(key);
    _expiry.remove(key);
  }

  static bool has(final String key) {
    if (_expiry.containsKey(key)) {
      if (DateTime.now().isAfter(_expiry[key]!)) {
        _cache.remove(key);
        _expiry.remove(key);
        return false;
      }
    }
    return _cache.containsKey(key);
  }
}

/// Fake File Storage Service for testing file operations
class FakeFileStorage {
  static final Map<String, String> _files = <String, String>{};
  static final Map<String, List<int>> _binaryFiles = <String, List<int>>{};

  static void clear() {
    _files.clear();
    _binaryFiles.clear();
  }

  static Future<void> writeString(
    final String path,
    final String content,
  ) async {
    _files[path] = content;
  }

  static Future<String?> readString(final String path) async {
    return _files[path];
  }

  static Future<void> writeBytes(
    final String path,
    final List<int> bytes,
  ) async {
    _binaryFiles[path] = bytes;
  }

  static Future<List<int>?> readBytes(final String path) async {
    return _binaryFiles[path];
  }

  static Future<bool> exists(final String path) async {
    return _files.containsKey(path) || _binaryFiles.containsKey(path);
  }

  static Future<void> delete(final String path) async {
    _files.remove(path);
    _binaryFiles.remove(path);
  }

  static List<String> listFiles() {
    return [..._files.keys, ..._binaryFiles.keys];
  }
}
