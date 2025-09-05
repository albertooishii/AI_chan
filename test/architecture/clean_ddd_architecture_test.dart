import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('🏗️ DDD Hexagonal Architecture Tests', () {
    test('🎯 Domain Layer: Must be completely isolated', () {
      final violations = <String>[];
      final domainFiles = _findFilesInLayer('domain');

      for (final file in domainFiles) {
        final content = file.readAsStringSync();

        // Domain NEVER depends on anything outside itself
        final forbiddenPatterns = [
          'package:flutter/',
          'package:provider/',
          '/infrastructure/',
          '/application/',
          '/presentation/',
          'dart:io',
          'dart:html',
        ];

        for (final pattern in forbiddenPatterns) {
          if (content.contains('import') && content.contains(pattern)) {
            violations.add(
              '❌ ${_getRelativePath(file)}: Forbidden dependency: $pattern',
            );
          }
        }

        // Domain entities must be pure
        if (file.path.contains('/entities/') ||
            file.path.contains('/models/')) {
          final impurePatterns = [
            'ChangeNotifier',
            'ValueNotifier',
            'async ',
            'Future<',
          ];
          for (final pattern in impurePatterns) {
            if (content.contains(pattern)) {
              violations.add(
                '❌ ${_getRelativePath(file)}: Domain entity is impure: $pattern',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 DOMAIN LAYER PURITY VIOLATIONS:
${violations.join('\n')}

DOMAIN MUST BE PURE BUSINESS LOGIC
      ''',
      );
    });

    test('🔄 Application Layer: Only depends on Domain interfaces', () {
      final violations = <String>[];
      final applicationFiles = _findFilesInLayer('application');

      for (final file in applicationFiles) {
        final content = file.readAsStringSync();

        // Application forbidden dependencies
        final forbiddenPatterns = [
          '/infrastructure/',
          '/presentation/',
          'dart:io',
          'dart:html',
        ];

        for (final pattern in forbiddenPatterns) {
          if (content.contains('import') && content.contains(pattern)) {
            violations.add(
              '❌ ${_getRelativePath(file)}: Forbidden dependency: $pattern',
            );
          }
        }

        // Application services must use interfaces
        if (file.path.contains('/services/')) {
          final concreteUsage = [
            'new SharedPreferences',
            'new File(',
            'new Directory(',
          ];

          for (final usage in concreteUsage) {
            if (content.contains(usage)) {
              violations.add(
                '❌ ${_getRelativePath(file)}: Using concrete infrastructure: $usage',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 APPLICATION LAYER VIOLATIONS:
${violations.join('\n')}

APPLICATION LAYER RULES:
- Only depends on Domain interfaces
- No direct infrastructure access
      ''',
      );
    });

    test('🔌 Infrastructure: Implements Domain interfaces', () {
      final violations = <String>[];
      final infraFiles = _findFilesInLayer('infrastructure');

      // Check that repositories implement interfaces
      for (final file in infraFiles) {
        if (file.path.contains('repository')) {
          final content = file.readAsStringSync();

          if (!content.contains('implements I')) {
            violations.add(
              '❌ ${_getRelativePath(file)}: Repository doesn\'t implement interface',
            );
          }
        }
      }

      // Check critical implementations exist
      final criticalInterfaces = ['IChatRepository', 'IPromptBuilderService'];
      for (final interface in criticalInterfaces) {
        final hasImplementation = infraFiles.any((file) {
          final content = file.readAsStringSync();
          return content.contains('implements $interface');
        });

        if (!hasImplementation) {
          violations.add('❌ Missing implementation for: $interface');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 INFRASTRUCTURE VIOLATIONS:
${violations.join('\n')}

INFRASTRUCTURE MUST IMPLEMENT DOMAIN INTERFACES
      ''',
      );
    });

    test('🎨 Presentation: Only UI, uses Application services', () {
      final violations = <String>[];
      final presentationFiles = _findFilesInLayer('presentation');

      for (final file in presentationFiles) {
        final content = file.readAsStringSync();

        // Presentation should not have business logic
        final businessLogicPatterns = [
          'SharedPreferences.',
          'http.get(',
          'http.post(',
          'Directory(',
        ];

        for (final pattern in businessLogicPatterns) {
          if (content.contains(pattern)) {
            violations.add(
              '❌ ${_getRelativePath(file)}: Contains business logic: $pattern',
            );
          }
        }

        // Check for File constructor usage (but not method calls like deleteFile(), importJsonFile(), etc.)
        // Pattern: File( but not preceded by alphanumeric/underscore (to exclude method calls)
        final fileConstructorRegex = RegExp(r'(?<![a-zA-Z0-9_])File\s*\(');
        if (fileConstructorRegex.hasMatch(content)) {
          violations.add(
            '❌ ${_getRelativePath(file)}: Contains business logic: File( constructor',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 PRESENTATION LAYER VIOLATIONS:
${violations.join('\n')}

PRESENTATION RULES:
- Only UI and user interaction logic
- Uses application services for business operations
      ''',
      );
    });

    test('🏛️ Dependency Inversion: Abstractions not concretions', () {
      final violations = <String>[];
      final applicationFiles = _findFilesInLayer('application');

      for (final file in applicationFiles) {
        if (file.path.contains('/services/')) {
          final content = file.readAsStringSync();

          // Check constructor dependencies
          final concreteTypes = [
            'ChatRepository(',
            'PromptBuilderService(',
            'SharedPreferences',
          ];

          for (final concreteType in concreteTypes) {
            if (content.contains(concreteType) &&
                content.contains('required') &&
                !content.contains('I$concreteType')) {
              violations.add(
                '❌ ${_getRelativePath(file)}: Depends on concrete type: $concreteType',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 DEPENDENCY INVERSION VIOLATIONS:
${violations.join('\n')}

HIGH-LEVEL MODULES MUST NOT DEPEND ON LOW-LEVEL MODULES
      ''',
      );
    });

    test('🧪 Clean Architecture: Critical validations', () {
      final missingValidations = <String>[];

      // Verify critical interfaces exist
      final requiredInterfaces = [
        'lib/chat/domain/interfaces/i_chat_repository.dart',
        'lib/chat/domain/interfaces/i_prompt_builder_service.dart',
      ];

      for (final interfacePath in requiredInterfaces) {
        if (!File(interfacePath).existsSync()) {
          missingValidations.add(
            '❌ Missing critical interface: $interfacePath',
          );
        }
      }

      // Verify layer separation
      final requiredLayers = [
        'lib/chat/domain',
        'lib/chat/application',
        'lib/chat/infrastructure',
        'lib/chat/presentation',
      ];

      for (final layer in requiredLayers) {
        if (!Directory(layer).existsSync()) {
          missingValidations.add('❌ Missing layer: $layer');
        }
      }

      expect(
        missingValidations,
        isEmpty,
        reason:
            '''
🚨 CLEAN ARCHITECTURE VIOLATIONS:
${missingValidations.join('\n')}

REQUIRED FOR CLEAN ARCHITECTURE:
- All critical interfaces defined
- All layers properly separated
      ''',
      );
    });
  });
}

List<File> _findFilesInLayer(String layer) {
  final files = <File>[];
  final layerDir = Directory('lib');

  if (!layerDir.existsSync()) return files;

  for (final entity in layerDir.listSync(recursive: true)) {
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        entity.path.contains('/$layer/') &&
        !entity.path.contains('/test/')) {
      files.add(entity);
    }
  }

  return files;
}

String _getRelativePath(File file) {
  return file.path.replaceFirst(RegExp(r'^.*lib/'), 'lib/');
}
