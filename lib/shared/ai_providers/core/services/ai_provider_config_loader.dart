/// Service for loading and validating AI Providers configuration from YAML files.
/// This service handles loading the ai_providers_config.yaml file and converting it
/// to strongly-typed configuration models.
library;

import 'dart:io';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_config.dart';
import 'package:ai_chan/core/config.dart'; // ✅ AGREGADO Config import

/// Exception thrown when configuration loading fails
class ConfigurationLoadException implements Exception {
  const ConfigurationLoadException(this.message, [this.innerException]);

  final String message;
  final dynamic innerException;

  @override
  String toString() =>
      'ConfigurationLoadException: $message'
      '${innerException != null ? ' (${innerException.toString()})' : ''}';
}

/// Service for loading AI provider configuration from YAML
class AIProviderConfigLoader {
  /// Configuration file path in assets
  static const String _defaultConfigPath = 'assets/ai_providers_config.yaml';

  /// Flag to skip environment validation during tests
  static bool skipEnvironmentValidation = false;

  /// Load default configuration from assets
  static Future<AIProvidersConfig> loadDefault() async {
    return loadFromAssets();
  }

  /// Load configuration from assets
  static Future<AIProvidersConfig> loadFromAssets({
    final String configPath = _defaultConfigPath,
  }) async {
    try {
      Log.i('Loading AI providers configuration from assets: $configPath');

      final String yamlString = await rootBundle.loadString(configPath);
      return _parseConfiguration(yamlString);
    } on Exception catch (e) {
      Log.e('Failed to load configuration from assets', error: e);
      throw ConfigurationLoadException(
        'Failed to load configuration from assets at $configPath',
        e,
      );
    }
  }

  /// Load configuration from file system
  static Future<AIProvidersConfig> loadFromFile(final String filePath) async {
    try {
      Log.i('Loading AI providers configuration from file: $filePath');

      final file = File(filePath);
      if (!file.existsSync()) {
        throw ConfigurationLoadException(
          'Configuration file not found: $filePath',
        );
      }

      final String yamlString = await file.readAsString();
      return _parseConfiguration(yamlString);
    } on Exception catch (e) {
      Log.e('Failed to load configuration from file', error: e);
      if (e is ConfigurationLoadException) rethrow;
      throw ConfigurationLoadException(
        'Failed to load configuration from file: $filePath',
        e,
      );
    }
  }

  /// Load configuration from YAML string
  static AIProvidersConfig loadFromString(final String yamlString) {
    try {
      Log.i('Loading AI providers configuration from string');
      return _parseConfiguration(yamlString);
    } on Exception catch (e) {
      Log.e('Failed to parse configuration string', error: e);
      if (e is ConfigurationLoadException) rethrow;
      throw ConfigurationLoadException(
        'Failed to parse configuration string',
        e,
      );
    }
  }

  /// Parse YAML string into configuration model
  static AIProvidersConfig _parseConfiguration(final String yamlString) {
    try {
      // Parse YAML
      final dynamic yamlDoc = loadYaml(yamlString);

      if (yamlDoc is! YamlMap) {
        throw const ConfigurationLoadException(
          'Configuration must be a YAML map/object',
        );
      }

      // Convert to Map<String, dynamic>
      final Map<String, dynamic> configMap = _yamlToMap(yamlDoc);

      // Validate basic structure
      _validateBasicStructure(configMap);

      // Apply environment overrides
      final processedConfig = _applyEnvironmentOverrides(configMap);

      // Validate environment variables
      _validateEnvironmentVariables(processedConfig);

      // Create configuration object
      return AIProvidersConfig.fromMap(processedConfig);
    } on Exception catch (e) {
      Log.e('Failed to parse YAML configuration', error: e);
      if (e is ConfigurationLoadException) rethrow;
      throw ConfigurationLoadException('Failed to parse YAML configuration', e);
    }
  }

  /// Convert YAML nodes to dynamic (preserving structure)
  static dynamic _yamlToMap(final dynamic yamlNode) {
    if (yamlNode is YamlMap) {
      final map = <String, dynamic>{};
      for (final entry in yamlNode.entries) {
        map[entry.key.toString()] = _yamlToMap(entry.value);
      }
      return map;
    } else if (yamlNode is YamlList) {
      return yamlNode.map(_yamlToMap).toList();
    } else {
      return yamlNode;
    }
  }

  /// Validate basic YAML structure
  static void _validateBasicStructure(final Map<String, dynamic> configMap) {
    final errors = <String>[];

    // Check required top-level keys
    final requiredKeys = [
      'version',
      'metadata',
      'global_settings',
      'ai_providers',
      'fallback_chains',
    ];
    for (final key in requiredKeys) {
      if (!configMap.containsKey(key)) {
        errors.add('Missing required key: $key');
      }
    }

    // Validate version format
    if (configMap.containsKey('version')) {
      final version = configMap['version'];
      if (version is! String || !RegExp(r'^\d+\.\d+$').hasMatch(version)) {
        errors.add(
          'Invalid version format. Expected format: X.Y (e.g., "1.0")',
        );
      }
    }

    // Validate ai_providers structure
    if (configMap.containsKey('ai_providers')) {
      final providers = configMap['ai_providers'];
      if (providers is! Map) {
        errors.add('ai_providers must be a map/object');
      } else {
        final providerMap = providers as Map<String, dynamic>;
        if (providerMap.isEmpty) {
          errors.add('ai_providers cannot be empty');
        }

        // Validate each provider
        for (final entry in providerMap.entries) {
          final providerKey = entry.key;
          final providerConfig = entry.value;

          if (providerConfig is! Map) {
            errors.add(
              'Provider "$providerKey" configuration must be a map/object',
            );
            continue;
          }

          final provider = providerConfig as Map<String, dynamic>;
          final requiredProviderKeys = [
            'enabled',
            'priority',
            'display_name',
            'capabilities',
          ];
          for (final key in requiredProviderKeys) {
            if (!provider.containsKey(key)) {
              errors.add('Provider "$providerKey" missing required key: $key');
            }
          }
        }
      }
    }

    if (errors.isNotEmpty) {
      throw ConfigurationLoadException(
        'Configuration validation failed:\n${errors.join('\n')}',
      );
    }
  }

  /// Apply environment overrides to configuration
  static AIProvidersConfig applyEnvironmentOverrides(
    final AIProvidersConfig config,
    final String environment,
  ) {
    // Convert config to map, apply overrides, and convert back
    final configMap = config.toMap();
    final processedMap = _applyEnvironmentOverridesMap(configMap, environment);
    return AIProvidersConfig.fromMap(processedMap);
  }

  /// Apply environment-specific overrides
  static Map<String, dynamic> _applyEnvironmentOverrides(
    final Map<String, dynamic> configMap,
  ) {
    // Determine current environment (default to 'development')
    final currentEnv = Platform.environment['AI_CHAN_ENV'] ?? 'development';
    return _applyEnvironmentOverridesMap(configMap, currentEnv);
  }

  /// Apply environment-specific overrides with specified environment
  static Map<String, dynamic> _applyEnvironmentOverridesMap(
    final Map<String, dynamic> configMap,
    final String environment,
  ) {
    final result = Map<String, dynamic>.from(configMap);

    // Check for environment-specific configurations
    final environments = configMap['environments'] as Map<String, dynamic>?;
    if (environments == null) return result;

    // Use specified environment
    final currentEnv = environment;
    Log.i('Applying environment overrides for: $currentEnv');
    final envConfig = environments[currentEnv] as Map<String, dynamic>?;
    if (envConfig == null) {
      Log.w('No configuration found for environment: $currentEnv');
      return result;
    }

    // Apply global settings overrides
    if (envConfig.containsKey('global_settings')) {
      final globalOverrides =
          envConfig['global_settings'] as Map<String, dynamic>;
      final existingGlobal = result['global_settings'] as Map<String, dynamic>;
      result['global_settings'] = {...existingGlobal, ...globalOverrides};
      Log.d('Applied global settings overrides: ${globalOverrides.keys}');
    }

    // Apply provider-specific overrides
    if (envConfig.containsKey('ai_providers')) {
      final providerOverrides =
          envConfig['ai_providers'] as Map<String, dynamic>;
      final existingProviders = result['ai_providers'] as Map<String, dynamic>;

      for (final entry in providerOverrides.entries) {
        final providerKey = entry.key;
        final overrides = entry.value as Map<String, dynamic>;

        if (existingProviders.containsKey(providerKey)) {
          final existingProvider =
              existingProviders[providerKey] as Map<String, dynamic>;
          final mergedProvider = Map<String, dynamic>.from(existingProvider);

          // Hacer merge profundo para campos específicos
          for (final overrideEntry in overrides.entries) {
            final overrideKey = overrideEntry.key;
            final overrideValue = overrideEntry.value;

            if (overrideKey == 'defaults' &&
                overrideValue is Map<String, dynamic> &&
                mergedProvider.containsKey('defaults') &&
                mergedProvider['defaults'] is Map<String, dynamic>) {
              // Merge profundo para defaults
              final existingDefaults =
                  mergedProvider['defaults'] as Map<String, dynamic>;
              mergedProvider['defaults'] = {
                ...existingDefaults,
                ...overrideValue,
              };
            } else {
              // Merge normal para otros campos
              mergedProvider[overrideKey] = overrideValue;
            }
          }

          existingProviders[providerKey] = mergedProvider;
          Log.d(
            'Applied overrides for provider "$providerKey": ${overrides.keys}',
          );
        } else {
          Log.w(
            'Environment override specified for unknown provider: $providerKey',
          );
        }
      }
    }

    return result;
  }

  /// Validate environment variables and return missing ones
  static List<String> validateEnvironmentVariables(
    final AIProvidersConfig config,
  ) {
    final missing = <String>[];

    for (final entry in config.aiProviders.entries) {
      final providerKey = entry.key;
      final provider = entry.value;

      // Skip disabled providers
      if (!provider.enabled) continue;

      // Check required environment variables
      for (final envKey in provider.apiSettings.requiredEnvKeys) {
        // ✅ CORREGIDO: Usar Config en lugar de Platform.environment
        final envValue = Config.get(envKey, '');
        if (envValue.isEmpty) {
          missing.add('$providerKey: $envKey');
        }
      }
    }

    return missing;
  }

  /// Validate that required environment variables are available
  static void _validateEnvironmentVariables(
    final Map<String, dynamic> configMap,
  ) {
    // Skip validation during tests
    if (skipEnvironmentValidation) {
      return;
    }

    final errors = <String>[];
    final providers = configMap['ai_providers'] as Map<String, dynamic>;

    for (final entry in providers.entries) {
      final providerKey = entry.key;
      final providerConfig = entry.value as Map<String, dynamic>;

      // Skip disabled providers
      if (providerConfig['enabled'] != true) continue;

      // Check required environment variables
      final apiSettings =
          providerConfig['api_settings'] as Map<String, dynamic>?;
      if (apiSettings != null) {
        final requiredEnvKeys = apiSettings['required_env_keys'] as List?;
        if (requiredEnvKeys != null) {
          for (final envKey in requiredEnvKeys) {
            // ✅ CORREGIDO: Usar Config en lugar de Platform.environment
            final envValue = Config.get(envKey.toString(), '');
            if (envValue.isEmpty) {
              errors.add(
                'Provider "$providerKey" requires environment variable: $envKey',
              );
            }
          }
        }
      }
    }

    if (errors.isNotEmpty) {
      throw ConfigurationLoadException(
        'Environment validation failed:\n${errors.join('\n')}\n\n'
        'Please ensure all required environment variables are set.',
      );
    }
  }

  /// Get configuration summary for debugging
  static Map<String, dynamic> getConfigSummary(final AIProvidersConfig config) {
    final summary = <String, dynamic>{
      'version': config.version,
      'total_providers': config.aiProviders.length,
      'enabled_providers': config.aiProviders.values
          .where((final p) => p.enabled)
          .length,
      'global_settings': {
        'default_timeout': config.globalSettings.defaultTimeoutSeconds,
        'max_retries': config.globalSettings.maxRetries,
        'fallback_enabled': config.globalSettings.enableFallback,
        'debug_mode': config.globalSettings.debugMode,
      },
      'providers': {},
      'fallback_chains': config.fallbackChains.map(
        (final k, final v) => MapEntry(k.name, {
          'primary': v.primary,
          'fallback_count': v.fallbacks.length,
        }),
      ),
    };

    // Add provider summary
    for (final entry in config.aiProviders.entries) {
      final provider = entry.value;
      summary['providers'][entry.key] = {
        'enabled': provider.enabled,
        'priority': provider.priority,
        'capabilities': provider.capabilities.map((final c) => c.name).toList(),
        'models_count': provider.models.values.fold(
          0,
          (final sum, final models) => sum + models.length,
        ),
      };
    }

    return summary;
  }

  /// Validate provider health (basic checks)
  static Future<Map<String, bool>> validateProviderHealth(
    final AIProvidersConfig config,
  ) async {
    final results = <String, bool>{};

    for (final entry in config.aiProviders.entries) {
      final providerKey = entry.key;
      final provider = entry.value;

      if (!provider.enabled) {
        results[providerKey] = false;
        continue;
      }

      try {
        // Basic validation - check if required environment variables exist
        bool isHealthy = true;
        for (final envKey in provider.apiSettings.requiredEnvKeys) {
          // ✅ CORREGIDO: Usar Config en lugar de Platform.environment
          final envValue = Config.get(envKey, '');
          if (envValue.isEmpty) {
            isHealthy = false;
            break;
          }
        }

        results[providerKey] = isHealthy;
        Log.d(
          'Provider "$providerKey" health check: ${isHealthy ? 'PASS' : 'FAIL'}',
        );
      } on Exception catch (e) {
        Log.e('Health check failed for provider "$providerKey"', error: e);
        results[providerKey] = false;
      }
    }

    return results;
  }
}
