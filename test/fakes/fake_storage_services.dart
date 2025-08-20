/// Fake SharedPreferences for testing storage operations
class FakeSharedPreferences {
  static final Map<String, dynamic> _storage = <String, dynamic>{};

  static void clear() {
    _storage.clear();
  }

  static void setInitialValues(Map<String, dynamic> values) {
    _storage.clear();
    _storage.addAll(values);
  }

  static Future<bool> setString(String key, String value) async {
    _storage[key] = value;
    return true;
  }

  static String? getString(String key) {
    return _storage[key] as String?;
  }

  static Future<bool> setBool(String key, bool value) async {
    _storage[key] = value;
    return true;
  }

  static bool? getBool(String key) {
    return _storage[key] as bool?;
  }

  static Future<bool> setInt(String key, int value) async {
    _storage[key] = value;
    return true;
  }

  static int? getInt(String key) {
    return _storage[key] as int?;
  }

  static Future<bool> remove(String key) async {
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

  static Future<void> set(String key, dynamic value, {Duration? ttl}) async {
    _cache[key] = value;
    if (ttl != null) {
      _expiry[key] = DateTime.now().add(ttl);
    }
  }

  static T? get<T>(String key) {
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

  static Future<void> remove(String key) async {
    _cache.remove(key);
    _expiry.remove(key);
  }

  static bool has(String key) {
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

  static Future<void> writeString(String path, String content) async {
    _files[path] = content;
  }

  static Future<String?> readString(String path) async {
    return _files[path];
  }

  static Future<void> writeBytes(String path, List<int> bytes) async {
    _binaryFiles[path] = bytes;
  }

  static Future<List<int>?> readBytes(String path) async {
    return _binaryFiles[path];
  }

  static Future<bool> exists(String path) async {
    return _files.containsKey(path) || _binaryFiles.containsKey(path);
  }

  static Future<void> delete(String path) async {
    _files.remove(path);
    _binaryFiles.remove(path);
  }

  static List<String> listFiles() {
    return [..._files.keys, ..._binaryFiles.keys];
  }
}
