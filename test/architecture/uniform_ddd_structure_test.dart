import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🏗️ UNIFORM DDD STRUCTURE VALIDATION
///
/// This test validates the uniform DDD structure implemented across
/// all bounded contexts to ensure consistency and maintainability.

void main() {
  group('🏗️ Uniform DDD Structure Validation', () {
    test('All bounded contexts must have identical DDD layer structure', () {
      final violations = <String>[];
      final boundedContexts = _findBoundedContexts();

      if (boundedContexts.isEmpty) {
        fail(
          'No bounded contexts found. Expected at least chat, voice, onboarding',
        );
      }

      // Expected uniform structure for all bounded contexts
      final expectedStructure = {
        'domain': ['interfaces', 'models', 'entities', 'enums', 'services'],
        'application': ['services', 'use_cases'],
        'infrastructure': ['adapters', 'services', 'utils'],
        'presentation': ['controllers', 'screens', 'widgets'],
      };

      for (final context in boundedContexts) {
        // Skip shared as it has a different purpose (shared kernel)
        if (context == 'shared') continue;

        final contextViolations = _validateContextStructure(
          context,
          expectedStructure,
        );
        violations.addAll(contextViolations);
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 UNIFORM DDD STRUCTURE VIOLATIONS:
${violations.join('\n')}

ALL BOUNDED CONTEXTS MUST HAVE UNIFORM STRUCTURE:
✅ domain/interfaces/ - Domain contracts and ports
✅ domain/models/ or domain/entities/ - Business objects
✅ domain/enums/ - Domain enumerations (if needed)
✅ application/services/ - Application layer coordination
✅ application/use_cases/ - Business operations
✅ infrastructure/adapters/ - External system implementations
✅ infrastructure/services/ - Technical services
✅ presentation/controllers/ - UI controllers
✅ presentation/screens/ - UI screens
✅ presentation/widgets/ - UI components

This ensures consistent architecture across all contexts.
        ''',
      );
    });

    test('Shared context must follow proper DDD shared kernel structure', () {
      final violations = <String>[];

      // Shared kernel has a different structure - it's cross-cutting
      final expectedSharedStructure = {
        'domain': ['models', 'interfaces', 'enums', 'constants'],
        'application': ['services'],
        'infrastructure': [
          'services',
          'utils',
          'adapters',
          'config',
          'di',
          'cache',
          'network',
        ],
        'presentation': ['widgets', 'screens', 'controllers'],
      };

      final sharedViolations = _validateSharedKernelStructure(
        expectedSharedStructure,
      );
      violations.addAll(sharedViolations);

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 SHARED KERNEL STRUCTURE VIOLATIONS:
${violations.join('\n')}

SHARED KERNEL MUST CONTAIN ONLY CROSS-CUTTING CONCERNS:
✅ domain/models/ - Shared business objects
✅ domain/interfaces/ - Cross-context contracts
✅ domain/enums/ - Shared enumerations
✅ domain/constants/ - Shared constants
✅ application/services/ - Cross-cutting application services
✅ infrastructure/services/ - Technical infrastructure
✅ infrastructure/utils/ - Shared utilities
✅ infrastructure/adapters/ - Shared technical adapters
✅ presentation/widgets/ - Reusable UI components

Shared context provides common functionality for all bounded contexts.
        ''',
      );
    });

    test('Legacy directories must be eliminated from all contexts', () {
      final violations = <String>[];
      final boundedContexts = _findBoundedContexts();

      // Legacy patterns that should no longer exist
      final legacyPatterns = [
        'services', // Should be application/services or infrastructure/services
        'utils', // Should be infrastructure/utils
        'constants', // Should be domain/constants
        'controllers', // Should be presentation/controllers
        'screens', // Should be presentation/screens
        'widgets', // Should be presentation/widgets
      ];

      for (final context in boundedContexts) {
        for (final pattern in legacyPatterns) {
          final legacyDir = Directory('lib/$context/$pattern');
          if (legacyDir.existsSync()) {
            violations.add(
              '❌ Legacy directory found: lib/$context/$pattern - should be moved to appropriate DDD layer',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 LEGACY DIRECTORY VIOLATIONS:
${violations.join('\n')}

LEGACY FLAT STRUCTURE HAS BEEN ELIMINATED:
❌ lib/{context}/services/ → ✅ lib/{context}/application/services/ or infrastructure/services/
❌ lib/{context}/utils/ → ✅ lib/{context}/infrastructure/utils/
❌ lib/{context}/constants/ → ✅ lib/{context}/domain/constants/
❌ lib/{context}/controllers/ → ✅ lib/{context}/presentation/controllers/
❌ lib/{context}/screens/ → ✅ lib/{context}/presentation/screens/
❌ lib/{context}/widgets/ → ✅ lib/{context}/presentation/widgets/

All contexts now use proper DDD layered architecture.
        ''',
      );
    });

    test('Barrel exports must reflect new DDD structure', () {
      final violations = <String>[];
      final boundedContexts = _findBoundedContexts();

      for (final context in boundedContexts) {
        final barrelFile = File('lib/$context.dart');
        if (barrelFile.existsSync()) {
          final content = barrelFile.readAsStringSync();

          // Check for legacy export patterns that should be updated
          final legacyExportPatterns = [
            RegExp('export.*/$context/services/'),
            RegExp('export.*/$context/utils/'),
            RegExp('export.*/$context/constants/'),
            RegExp('export.*/$context/controllers/'),
            RegExp('export.*/$context/screens/'),
            RegExp('export.*/$context/widgets/'),
          ];

          for (final pattern in legacyExportPatterns) {
            if (pattern.hasMatch(content)) {
              violations.add(
                '❌ Legacy export in lib/$context.dart: ${pattern.pattern}',
              );
            }
          }

          // Check for proper DDD exports
          final expectedExports = [
            'export \'$context/domain/',
            'export \'$context/application/',
            'export \'$context/infrastructure/',
            'export \'$context/presentation/',
          ];

          for (final expectedExport in expectedExports) {
            if (!content.contains(expectedExport)) {
              // Only warn if the layer actually exists
              if (_layerExists(context, expectedExport.split('/')[1])) {
                violations.add(
                  '⚠️ Missing DDD export in lib/$context.dart: $expectedExport',
                );
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 BARREL EXPORT VIOLATIONS:
${violations.join('\n')}

BARREL EXPORTS MUST REFLECT DDD STRUCTURE:
✅ export 'context/domain/...' - Domain layer exports
✅ export 'context/application/...' - Application layer exports  
✅ export 'context/infrastructure/...' - Infrastructure layer exports
✅ export 'context/presentation/...' - Presentation layer exports

❌ No legacy export patterns should remain.
        ''',
      );
    });

    test(
      'Import paths must use proper package imports, not relative paths',
      () {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final contextDir = Directory('lib/$context');
          if (contextDir.existsSync()) {
            final importViolations = _checkImportPatterns(context);
            violations.addAll(importViolations);
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 IMPORT PATH VIOLATIONS:
${violations.join('\n')}

IMPORT STANDARDS:
✅ package:ai_chan/{context}/... - For bounded context imports
✅ package:ai_chan/shared/... - For shared kernel imports
❌ ../../../ - Relative imports should be eliminated
❌ ../../ - Relative imports should be eliminated

All imports should use proper package imports for maintainability.
        ''',
        );
      },
    );

    test('Domain layer isolation must be maintained across all contexts', () {
      final violations = <String>[];
      final boundedContexts = _findBoundedContexts();

      for (final context in boundedContexts) {
        final domainDir = Directory('lib/$context/domain');
        if (domainDir.existsSync()) {
          final isolationViolations = _checkDomainIsolation(context);
          violations.addAll(isolationViolations);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 DOMAIN ISOLATION VIOLATIONS:
${violations.join('\n')}

DOMAIN ISOLATION RULES:
✅ Domain can only import from same context domain
✅ Domain can import from shared/core domain abstractions
❌ Domain CANNOT import from infrastructure layers
❌ Domain CANNOT import from presentation layers
❌ Domain CANNOT import from application layers
❌ Domain CANNOT import from other bounded contexts

Domain must remain pure and dependency-free.
        ''',
      );
    });
  });
}

List<String> _findBoundedContexts() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) return [];

  return libDir
      .listSync()
      .whereType<Directory>()
      .map((final d) => d.path.split('/').last)
      .where(
        (final name) =>
            !name.startsWith('.') &&
            name != 'main.dart' &&
            _isBoundedContext(name),
      )
      .toList();
}

bool _isBoundedContext(final String name) {
  final contextDir = Directory('lib/$name');
  return contextDir.existsSync() &&
      (Directory('lib/$name/domain').existsSync() ||
          Directory('lib/$name/application').existsSync());
}

List<String> _validateContextStructure(
  final String context,
  final Map<String, List<String>> expectedStructure,
) {
  final violations = <String>[];

  for (final layer in expectedStructure.keys) {
    final layerDir = Directory('lib/$context/$layer');

    // Check if layer exists (required layers)
    if (['domain', 'application'].contains(layer) && !layerDir.existsSync()) {
      violations.add('❌ Missing required layer: lib/$context/$layer/');
      continue;
    }

    // If layer exists, check subdirectories
    if (layerDir.existsSync()) {
      final expectedSubdirs = expectedStructure[layer]!;

      // Check for at least one expected subdirectory
      final hasAnyExpectedSubdir = expectedSubdirs.any(
        (final subdir) => Directory('lib/$context/$layer/$subdir').existsSync(),
      );

      if (!hasAnyExpectedSubdir && _layerHasFiles(context, layer)) {
        violations.add(
          '⚠️ Layer lib/$context/$layer/ has files but no proper subdirectory structure',
        );
      }
    }
  }

  return violations;
}

List<String> _validateSharedKernelStructure(
  final Map<String, List<String>> expectedStructure,
) {
  final violations = <String>[];

  for (final layer in expectedStructure.keys) {
    final layerDir = Directory('lib/shared/$layer');

    if (layerDir.existsSync()) {
      final expectedSubdirs = expectedStructure[layer]!;

      // Check for proper organization in shared kernel
      final hasProperStructure = expectedSubdirs.any(
        (final subdir) => Directory('lib/shared/$layer/$subdir').existsSync(),
      );

      if (!hasProperStructure && _layerHasFiles('shared', layer)) {
        violations.add(
          '⚠️ Shared layer lib/shared/$layer/ needs proper subdirectory structure',
        );
      }
    }
  }

  return violations;
}

bool _layerExists(final String context, final String layer) {
  return Directory('lib/$context/$layer').existsSync();
}

bool _layerHasFiles(final String context, final String layer) {
  final layerDir = Directory('lib/$context/$layer');
  if (!layerDir.existsSync()) return false;

  return layerDir
      .listSync(recursive: true)
      .any((final entity) => entity is File && entity.path.endsWith('.dart'));
}

List<String> _checkImportPatterns(final String context) {
  final violations = <String>[];
  final contextDir = Directory('lib/$context');

  for (final entity in contextDir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      final relativePath = entity.path.replaceFirst(RegExp(r'^.*lib/'), 'lib/');

      // Check for relative imports
      final lines = content.split('\n');
      for (final line in lines) {
        if (line.trim().startsWith('import') && line.contains('../')) {
          if (!_isAllowedRelativeImport(line, context)) {
            violations.add(
              '❌ $relativePath: Relative import should use package import: ${line.trim()}',
            );
          }
        }
      }

      // Check for legacy import paths that should be updated
      final legacyPaths = [
        'package:ai_chan/shared/utils/',
        'package:ai_chan/shared/services/',
        'package:ai_chan/shared/constants/',
        'package:ai_chan/shared/controllers/',
        'package:ai_chan/shared/screens/',
        'package:ai_chan/shared/widgets/',
      ];

      for (final legacyPath in legacyPaths) {
        if (content.contains(legacyPath)) {
          violations.add(
            '❌ $relativePath: Legacy import path should be updated to new DDD structure: $legacyPath',
          );
        }
      }
    }
  }

  return violations;
}

bool _isAllowedRelativeImport(final String importLine, final String context) {
  // Allow relative imports within the same layer for closely related files
  // e.g., ../interfaces/i_something.dart within infrastructure/adapters/
  return importLine.contains('../interfaces/') ||
      importLine.contains('../models/') ||
      importLine.contains('../entities/');
}

List<String> _checkDomainIsolation(final String context) {
  final violations = <String>[];
  final domainDir = Directory('lib/$context/domain');

  for (final entity in domainDir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      final relativePath = entity.path.replaceFirst(RegExp(r'^.*lib/'), 'lib/');

      // Check for forbidden imports in domain layer
      final forbiddenPaths = [
        '/$context/infrastructure/',
        '/$context/presentation/',
        '/$context/application/',
        'package:ai_chan/$context/infrastructure/',
        'package:ai_chan/$context/presentation/',
        'package:ai_chan/$context/application/',
      ];

      for (final forbiddenPath in forbiddenPaths) {
        if (content.contains(forbiddenPath)) {
          violations.add(
            '❌ $relativePath: Domain layer violates isolation by importing from other layers',
          );
        }
      }

      // Check for cross-context imports (other bounded contexts)
      final otherContexts = _findBoundedContexts()
          .where((final c) => c != context && c != 'shared')
          .toList();
      for (final otherContext in otherContexts) {
        if (content.contains('/$otherContext/')) {
          violations.add(
            '❌ $relativePath: Domain layer imports from other bounded context: $otherContext',
          );
        }
      }
    }
  }

  return violations;
}
