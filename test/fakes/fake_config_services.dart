/// Fake Configuration Service for testing app settings
class FakeConfigService {
  FakeConfigService({
    final Map<String, dynamic>? initialConfig,
    this.shouldFailOnRead = false,
    this.shouldFailOnWrite = false,
    this.errorMessage = 'Configuration operation failed',
  }) {
    if (initialConfig != null) {
      _config.addAll(initialConfig);
    }
  }

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
    final bool failReads = true,
    final bool failWrites = true,
    final String? errorMsg,
  }) {
    return FakeConfigService(
      shouldFailOnRead: failReads,
      shouldFailOnWrite: failWrites,
      errorMessage: errorMsg ?? 'Configuration service unavailable',
    );
  }
  final Map<String, dynamic> _config = <String, dynamic>{};
  final bool shouldFailOnRead;
  final bool shouldFailOnWrite;
  final String errorMessage;

  Future<T?> getValue<T>(final String key) async {
    if (shouldFailOnRead) {
      throw Exception(errorMessage);
    }
    return _config[key] as T?;
  }

  Future<void> setValue<T>(final String key, final T value) async {
    if (shouldFailOnWrite) {
      throw Exception(errorMessage);
    }
    _config[key] = value;
  }

  Future<void> removeValue(final String key) async {
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

  bool hasKey(final String key) => _config.containsKey(key);
}

/// Fake Settings Repository for testing settings persistence
class FakeSettingsRepository {
  FakeSettingsRepository({
    final Map<String, dynamic>? initialSettings,
    this.shouldFail = false,
    this.errorMessage = 'Settings operation failed',
  }) {
    if (initialSettings != null) {
      _settings.addAll(initialSettings);
    }
  }

  factory FakeSettingsRepository.failure([final String? errorMsg]) {
    return FakeSettingsRepository(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Settings repository unavailable',
    );
  }
  final Map<String, dynamic> _settings = <String, dynamic>{};
  final bool shouldFail;
  final String errorMessage;

  Future<Map<String, dynamic>> loadSettings() async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    return Map.from(_settings);
  }

  Future<void> saveSettings(final Map<String, dynamic> settings) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    _settings.clear();
    _settings.addAll(settings);
  }

  Future<void> updateSetting(final String key, final dynamic value) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    _settings[key] = value;
  }

  Future<void> deleteSetting(final String key) async {
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
}

/// Fake Theme Service for testing theme management
class FakeThemeService {
  FakeThemeService({
    final String? initialTheme,
    this.shouldFail = false,
    this.errorMessage = 'Theme service failed',
  }) {
    if (initialTheme != null && _availableThemes.contains(initialTheme)) {
      _currentTheme = initialTheme;
    }
  }

  factory FakeThemeService.dark() {
    return FakeThemeService(initialTheme: 'dark');
  }

  factory FakeThemeService.failure([final String? errorMsg]) {
    return FakeThemeService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Theme service unavailable',
    );
  }
  String _currentTheme = 'light';
  final List<String> _availableThemes = ['light', 'dark', 'system'];
  final bool shouldFail;
  final String errorMessage;

  String get currentTheme => _currentTheme;
  List<String> get availableThemes => List.from(_availableThemes);

  Future<void> setTheme(final String theme) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    if (!_availableThemes.contains(theme)) {
      throw ArgumentError('Theme "$theme" is not available');
    }

    _currentTheme = theme;
  }

  Future<bool> isThemeSupported(final String theme) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }
    return _availableThemes.contains(theme);
  }
}
