/// Fake Configuration Service for testing app settings
class FakeConfigService {
  final Map<String, dynamic> _config = <String, dynamic>{};
  final bool shouldFailOnRead;
  final bool shouldFailOnWrite;
  final String errorMessage;

  FakeConfigService({
    Map<String, dynamic>? initialConfig,
    this.shouldFailOnRead = false,
    this.shouldFailOnWrite = false,
    this.errorMessage = 'Configuration operation failed',
  }) {
    if (initialConfig != null) {
      _config.addAll(initialConfig);
    }
  }

  Future<T?> getValue<T>(String key) async {
    if (shouldFailOnRead) {
      throw Exception(errorMessage);
    }
    return _config[key] as T?;
  }

  Future<void> setValue<T>(String key, T value) async {
    if (shouldFailOnWrite) {
      throw Exception(errorMessage);
    }
    _config[key] = value;
  }

  Future<void> removeValue(String key) async {
    if (shouldFailOnWrite) {
      throw Exception(errorMessage);
    }
    _config.remove(key);
  }

  Future<void> clear() async {
    if (shouldFailOnWrite) {
      throw Exception(errorMessage);
    }
    _config.clear();
  }

  Map<String, dynamic> get allValues => Map.from(_config);

  bool hasKey(String key) => _config.containsKey(key);

  /// Factory for service with default settings
  factory FakeConfigService.withDefaults() {
    return FakeConfigService(
      initialConfig: {
        'theme': 'dark',
        'language': 'en',
        'auto_save': true,
        'max_tokens': 4096,
        'temperature': 0.7,
      },
    );
  }

  /// Factory for failing service
  factory FakeConfigService.failure({
    bool failReads = true,
    bool failWrites = true,
    String? errorMsg,
  }) {
    return FakeConfigService(
      shouldFailOnRead: failReads,
      shouldFailOnWrite: failWrites,
      errorMessage: errorMsg ?? 'Configuration service unavailable',
    );
  }
}

/// Fake Settings Repository for testing settings persistence
class FakeSettingsRepository {
  final Map<String, dynamic> _settings = <String, dynamic>{};
  final bool shouldFail;
  final String errorMessage;

  FakeSettingsRepository({
    Map<String, dynamic>? initialSettings,
    this.shouldFail = false,
    this.errorMessage = 'Settings operation failed',
  }) {
    if (initialSettings != null) {
      _settings.addAll(initialSettings);
    }
  }

  Future<Map<String, dynamic>> loadSettings() async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    return Map.from(_settings);
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    _settings.clear();
    _settings.addAll(settings);
  }

  Future<void> updateSetting(String key, dynamic value) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    _settings[key] = value;
  }

  Future<void> deleteSetting(String key) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    _settings.remove(key);
  }

  Future<void> resetToDefaults() async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    _settings.clear();
    _settings.addAll({
      'theme': 'light',
      'language': 'en',
      'notifications': true,
      'auto_backup': false,
    });
  }

  factory FakeSettingsRepository.failure([String? errorMsg]) {
    return FakeSettingsRepository(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Settings repository unavailable',
    );
  }
}

/// Fake Theme Service for testing theme management
class FakeThemeService {
  String _currentTheme = 'light';
  final List<String> _availableThemes = ['light', 'dark', 'system'];
  final bool shouldFail;
  final String errorMessage;

  FakeThemeService({
    String? initialTheme,
    this.shouldFail = false,
    this.errorMessage = 'Theme service failed',
  }) {
    if (initialTheme != null && _availableThemes.contains(initialTheme)) {
      _currentTheme = initialTheme;
    }
  }

  String get currentTheme => _currentTheme;
  List<String> get availableThemes => List.from(_availableThemes);

  Future<void> setTheme(String theme) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    if (!_availableThemes.contains(theme)) {
      throw ArgumentError('Theme "$theme" is not available');
    }

    _currentTheme = theme;
  }

  Future<bool> isThemeSupported(String theme) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    return _availableThemes.contains(theme);
  }

  factory FakeThemeService.dark() {
    return FakeThemeService(initialTheme: 'dark');
  }

  factory FakeThemeService.failure([String? errorMsg]) {
    return FakeThemeService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Theme service unavailable',
    );
  }
}
