import 'dart:io';
import 'package:test/test.dart';

/// 🎯 Test comprehensivo para detectar hardcoding y violaciones de desacoplamiento
///
/// Este test garantiza que:
/// 1. No hay listas hardcodeadas de modelos, voces, idiomas en el código
/// 2. Los datos vienen exclusivamente de providers o YAML (solo defaults)
/// 3. No hay URLs de API hardcodeadas fuera de providers
/// 4. No hay referencias directas a providers específicos fuera de registry
class ProviderDecouplingComprehensiveTest {
  /// Archivos que pueden contener hardcoding legítimo (providers y registry)
  static const List<String> _allowedHardcodingFiles = [
    'lib/shared/ai_providers/implementations/', // Providers pueden hardcodear sus propios datos
    'lib/shared/ai_providers/core/registry/', // Registry maneja providers
    'test/', // Tests pueden hardcodear para verificación
    'assets/ai_providers_config.yaml', // YAML puede tener defaults
  ];

  /// Archivos que deben estar libres de hardcoding específico
  static const List<String> _businessLogicPaths = [
    'lib/chat/',
    'lib/onboarding/',
    'lib/voice/',
    'lib/shared/services/',
    'lib/shared/infrastructure/utils/',
    'lib/shared/ai_providers/core/services/', // Services deben usar providers dinámicamente
  ];

  static void runAllTests() {
    group('🎯 Provider Decoupling - Comprehensive Hardcoding Detection', () {
      test('🔍 Should not have hardcoded voice lists outside providers', () {
        final violations = _findHardcodedVoices();

        if (violations.isNotEmpty) {
          final report = violations
              .map((v) => '❌ ${v.file}:${v.line} - ${v.content}')
              .join('\n');
          fail('Found hardcoded voice lists outside providers:\n$report');
        }
      });

      test('🔍 Should not have hardcoded model lists outside providers', () {
        final violations = _findHardcodedModels();

        if (violations.isNotEmpty) {
          final report = violations
              .map((v) => '❌ ${v.file}:${v.line} - ${v.content}')
              .join('\n');
          fail('Found hardcoded model lists outside providers:\n$report');
        }
      });

      test('🔍 Should not have hardcoded language lists outside providers', () {
        final violations = _findHardcodedLanguages();

        if (violations.isNotEmpty) {
          final report = violations
              .map((v) => '❌ ${v.file}:${v.line} - ${v.content}')
              .join('\n');
          fail('Found hardcoded language lists outside providers:\n$report');
        }
      });

      test('🔍 Should not have hardcoded API URLs outside providers', () {
        final violations = _findHardcodedApiUrls();

        if (violations.isNotEmpty) {
          final report = violations
              .map((v) => '❌ ${v.file}:${v.line} - ${v.content}')
              .join('\n');
          fail('Found hardcoded API URLs outside providers:\n$report');
        }
      });

      test(
        '🔍 Should not have direct provider references in business logic',
        () {
          final violations = _findDirectProviderReferences();

          if (violations.isNotEmpty) {
            final report = violations
                .map((v) => '❌ ${v.file}:${v.line} - ${v.content}')
                .join('\n');
            fail(
              'Found direct provider references in business logic:\n$report',
            );
          }
        },
      );

      test('🔍 Should not have duck typing with specific provider types', () {
        final violations = _findDuckTypingViolations();

        if (violations.isNotEmpty) {
          final report = violations
              .map((v) => '❌ ${v.file}:${v.line} - ${v.content}')
              .join('\n');
          fail(
            'Found duck typing violations with specific provider types:\n$report',
          );
        }
      });

      test(' Generate comprehensive hardcoding report', () {
        final report = _generateComprehensiveReport();
        print('\n📊 COMPREHENSIVE HARDCODING ANALYSIS REPORT:\n$report');
      });
    });
  }

  /// Detecta listas hardcodeadas de voces (nova, alloy, marin, etc.)
  static List<HardcodingViolation> _findHardcodedVoices() {
    final violations = <HardcodingViolation>[];

    final files = _getBusinessLogicFiles();
    for (final file in files) {
      if (_isAllowedHardcodingFile(file.path)) continue;

      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Check for OpenAI voice names in strings
        final voiceNames = [
          'nova',
          'alloy',
          'marin',
          'echo',
          'shimmer',
          'onyx',
          'sage',
          'cedar',
        ];
        for (final voice in voiceNames) {
          if (line.contains('"$voice"') || line.contains("'$voice'")) {
            // Skip comments
            if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
              continue;
            }

            violations.add(
              HardcodingViolation(
                file: file.path,
                line: i + 1,
                content: line.trim(),
                type: 'HARDCODED_VOICES',
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Detecta listas hardcodeadas de modelos (gpt-4, gemini-2.5, etc.)
  static List<HardcodingViolation> _findHardcodedModels() {
    final violations = <HardcodingViolation>[];

    final files = _getBusinessLogicFiles();
    for (final file in files) {
      if (_isAllowedHardcodingFile(file.path)) continue;

      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Check for model names in strings
        final modelPatterns = [
          'gpt-4',
          'gpt-5',
          'gemini-2',
          'grok-',
          'dall-e',
          'whisper-',
          'tts-1',
        ];
        for (final model in modelPatterns) {
          if ((line.contains('"$model') || line.contains("'$model")) &&
              !line.contains('//')) {
            violations.add(
              HardcodingViolation(
                file: file.path,
                line: i + 1,
                content: line.trim(),
                type: 'HARDCODED_MODELS',
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Detecta listas hardcodeadas de idiomas
  static List<HardcodingViolation> _findHardcodedLanguages() {
    final violations = <HardcodingViolation>[];

    final files = _getBusinessLogicFiles();
    for (final file in files) {
      if (_isAllowedHardcodingFile(file.path)) continue;

      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Check for language arrays specifically
        if (line.contains('supportedLanguages') ||
            (line.contains('List<String>') && line.contains('['))) {
          final languageCodes = [
            'en',
            'es',
            'fr',
            'de',
            'it',
            'pt',
            'zh',
            'ja',
            'ko',
            'ru',
            'ar',
          ];
          var languageCount = 0;
          for (final lang in languageCodes) {
            if (line.contains("'$lang'") || line.contains('"$lang"')) {
              languageCount++;
            }
          }

          // If has 3+ languages, likely a hardcoded list
          if (languageCount >= 3) {
            violations.add(
              HardcodingViolation(
                file: file.path,
                line: i + 1,
                content: line.trim(),
                type: 'HARDCODED_LANGUAGES',
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Detecta URLs de API hardcodeadas fuera de providers
  static List<HardcodingViolation> _findHardcodedApiUrls() {
    final violations = <HardcodingViolation>[];

    final files = _getBusinessLogicFiles();
    for (final file in files) {
      if (_isAllowedHardcodingFile(file.path)) continue;

      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Check for API URLs
        final apiUrls = [
          'https://api.openai.com',
          'https://generativelanguage.googleapis.com',
          'https://api.x.ai',
          'https://texttospeech.googleapis.com',
        ];

        for (final url in apiUrls) {
          if (line.contains(url) && !line.trim().startsWith('//')) {
            violations.add(
              HardcodingViolation(
                file: file.path,
                line: i + 1,
                content: line.trim(),
                type: 'HARDCODED_API_URLS',
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Detecta referencias directas a providers en lógica de negocio
  static List<HardcodingViolation> _findDirectProviderReferences() {
    final violations = <HardcodingViolation>[];

    final files = _getBusinessLogicFiles();
    for (final file in files) {
      if (_isAllowedHardcodingFile(file.path)) continue;
      if (file.path.contains('test/')) {
        continue; // Tests pueden referenciar providers
      }

      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip comments and strings that are just documentation
        if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
          continue;
        }

        final providers = ['openai', 'google', 'gemini', 'xai', 'grok'];
        for (final provider in providers) {
          if ((line.contains('"$provider"') || line.contains("'$provider'")) &&
              (line.contains('provider') ||
                  line.contains('Provider') ||
                  line.contains('getProvider'))) {
            violations.add(
              HardcodingViolation(
                file: file.path,
                line: i + 1,
                content: line.trim(),
                type: 'DIRECT_PROVIDER_REFERENCE',
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Detecta duck typing con tipos específicos de providers (ej: provider is OpenAIProviderVoices)
  static List<HardcodingViolation> _findDuckTypingViolations() {
    final violations = <HardcodingViolation>[];

    final files = _getBusinessLogicFiles();
    for (final file in files) {
      if (_isAllowedHardcodingFile(file.path)) continue;
      if (file.path.contains('test/')) {
        continue; // Tests pueden referenciar providers
      }

      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip comments
        if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
          continue;
        }

        // Detect generic duck typing patterns that suggest provider-specific coupling
        final duckTypingPatterns = [
          // Pattern 1: "provider is SomethingProvider*" - detects provider-specific type checks
          RegExp(
            r'provider\s+is\s+[A-Z]\w*Provider(?:Voices?|Audio|Text|Image|Chat|Vision|Embedding|Realtime|API|Client|SDK)\w*',
            caseSensitive: false,
          ),
          // Pattern 2: "(provider as SomethingProvider*)" - detects provider-specific casts
          RegExp(
            r'\(provider\s+as\s+[A-Z]\w*Provider(?:Voices?|Audio|Text|Image|Chat|Vision|Embedding|Realtime|API|Client|SDK)\w*\)',
            caseSensitive: false,
          ),
          // Pattern 3: Interface/class names like "CompanyProvider*" with AI capabilities
          RegExp(
            r'\b[A-Z]\w*Provider(?:Voices?|Audio|Text|Image|Chat|Vision|Embedding|Realtime|API|Client|SDK)\w*\b',
          ),
          // Pattern 4: Class/interface declarations with AI provider pattern
          RegExp(
            r'(?:class|interface|abstract)\s+[A-Z]\w*Provider(?:Voices?|Audio|Text|Image|Chat|Vision|Embedding|Realtime|API|Client|SDK)\w*',
          ),
        ];

        for (final pattern in duckTypingPatterns) {
          if (pattern.hasMatch(line)) {
            // Additional validation: ignore generic provider interfaces that are allowed
            if (_isGenericProviderInterface(line)) {
              continue;
            }

            violations.add(
              HardcodingViolation(
                file: file.path,
                line: i + 1,
                content: line.trim(),
                type: 'DUCK_TYPING_VIOLATION',
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Verifica si una línea contiene una interfaz genérica permitida
  static bool _isGenericProviderInterface(String line) {
    // Allow truly generic interfaces that don't mention specific providers
    final allowedGenericPatterns = [
      'IAIProvider', // Main provider interface
      'TTSVoiceProvider', // Generic voice provider interface
      'RealtimeProvider', // Generic realtime interface
      'TextProvider', // Generic text interface
      'AudioProvider', // Generic audio interface (if truly generic)
      'AIProviderManager', // Manager is allowed to handle providers
      'AIProviderFactory', // Factory is allowed to create providers
      'AIProviderService', // Generic service allowed
      'AIProviderConfigLoader', // Config loader allowed
      'ProviderAutoRegistry', // Auto registry is infrastructure
      'NoProviderAvailableException', // Exception class allowed
      '_ProviderHealthTracker', // Internal health tracking
      '_ProviderStats', // Internal stats
    ];

    // Also reject if it contains company/product names (this catches Meta, etc.)
    final companyNames = [
      'OpenAI',
      'Google',
      'Gemini',
      'Anthropic',
      'Claude',
      'XAI',
      'Grok',
      'Cohere',
      'Meta',
      'Llama',
      'Microsoft',
      'Azure',
      'AWS',
      'Bedrock',
    ];
    final hasCompanyName = companyNames.any(
      (company) => line.toLowerCase().contains(company.toLowerCase()),
    );

    return allowedGenericPatterns.any((pattern) => line.contains(pattern)) &&
        !hasCompanyName;
  }

  /// Genera un reporte comprehensivo de todo el hardcoding encontrado
  static String _generateComprehensiveReport() {
    final report = StringBuffer();

    final allViolations = <HardcodingViolation>[];
    allViolations.addAll(_findHardcodedVoices());
    allViolations.addAll(_findHardcodedModels());
    allViolations.addAll(_findHardcodedLanguages());
    allViolations.addAll(_findHardcodedApiUrls());
    allViolations.addAll(_findDirectProviderReferences());

    // Agrupar por tipo
    final violationsByType = <String, List<HardcodingViolation>>{};
    for (final violation in allViolations) {
      violationsByType.putIfAbsent(violation.type, () => []).add(violation);
    }

    report.writeln('📊 TOTAL VIOLATIONS FOUND: ${allViolations.length}');
    report.writeln();

    for (final entry in violationsByType.entries) {
      final type = entry.key;
      final violations = entry.value;

      report.writeln('🔍 $type (${violations.length} violations):');
      for (final violation in violations) {
        report.writeln(
          '   ❌ ${_getRelativePath(violation.file)}:${violation.line}',
        );
        report.writeln('      ${violation.content}');
      }
      report.writeln();
    }

    // Resumen por archivo
    final violationsByFile = <String, List<HardcodingViolation>>{};
    for (final violation in allViolations) {
      violationsByFile.putIfAbsent(violation.file, () => []).add(violation);
    }

    report.writeln('📁 VIOLATIONS BY FILE:');
    for (final entry in violationsByFile.entries) {
      final file = entry.key;
      final violations = entry.value;
      report.writeln(
        '   📄 ${_getRelativePath(file)} (${violations.length} violations)',
      );
    }

    return report.toString();
  }

  /// Obtiene archivos de lógica de negocio que deben estar libres de hardcoding
  static List<File> _getBusinessLogicFiles() {
    final files = <File>[];

    for (final path in _businessLogicPaths) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        final dartFiles = dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        files.addAll(dartFiles);
      }
    }

    return files;
  }

  /// Verifica si un archivo puede contener hardcoding legítimo
  static bool _isAllowedHardcodingFile(String filePath) {
    for (final allowedPath in _allowedHardcodingFiles) {
      if (filePath.contains(allowedPath)) {
        return true;
      }
    }
    return false;
  }

  /// Obtiene path relativo para reportes más legibles
  static String _getRelativePath(String fullPath) {
    final projectRoot = Directory.current.path;
    return fullPath
        .replaceFirst(projectRoot, '')
        .replaceFirst(RegExp(r'^/'), '');
  }
}

/// Representa una violación de desacoplamiento encontrada
class HardcodingViolation {
  const HardcodingViolation({
    required this.file,
    required this.line,
    required this.content,
    required this.type,
  });
  final String file;
  final int line;
  final String content;
  final String type;

  @override
  String toString() => '$type: $file:$line - $content';
}

void main() {
  ProviderDecouplingComprehensiveTest.runAllTests();
}
