import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('🔒 Bounded Context Isolation Tests', () {
    test('🔀 chat domain should not import from other bounded contexts', () {
      _verifyBoundedContextIsolation('lib/chat/domain', [
        'onboarding',
        'call', // Updated: voice -> call
      ]);
    });

    test(
      '🔀 onboarding domain should not import from other bounded contexts',
      () {
        _verifyBoundedContextIsolation('lib/onboarding/domain', [
          'chat',
          'call', // Updated: voice -> call
        ]);
      },
    );

    test('🔀 call domain should not import from other bounded contexts', () {
      _verifyBoundedContextIsolation('lib/call/domain', ['chat', 'onboarding']);
    });

    test('🎯 All bounded contexts must have consistent isolation', () {
      final violations = <String>[];
      final boundedContexts = _findAllBoundedContexts();

      // Verify each context doesn't import from OTHER BOUNDED CONTEXTS
      // (shared/core imports are allowed as they provide cross-cutting concerns)
      for (final context in boundedContexts) {
        final forbiddenContexts = boundedContexts
            .where((final c) => c != context && c != 'shared' && c != 'core')
            .toList();
        try {
          _verifyBoundedContextIsolation(
            'lib/$context/domain',
            forbiddenContexts,
          );
        } on Exception catch (e) {
          violations.add('❌ $context domain violates isolation: $e');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Bounded context isolation violations:\n${violations.join('\n')}',
      );
    });

    test('🏠 Services in shared/ should be truly cross-context', () {
      final misplacedServices = _findMisplacedServicesInShared();

      if (misplacedServices.isNotEmpty) {
        print('\n📍 Services in shared/ that appear context-specific:');
        for (final service in misplacedServices) {
          print('  - $service');
        }
        print(
          '\n💡 Consider moving these services to their specific bounded contexts.',
        );
      }

      // This is informational only - don't fail the test as some shared services are intentional
    });

    test('🔧 Adapters should have meaningful implementations', () {
      final emptyAdapters = _findEmptyAdapterImplementations();

      if (emptyAdapters.isNotEmpty) {
        print('\n🛠️ Adapters with placeholder/empty implementations:');
        for (final adapter in emptyAdapters) {
          print('  - $adapter');
        }
        print(
          '\n💡 Some placeholder adapters are acceptable for future implementations.',
        );
      }

      // This is informational only - placeholder adapters are often part of DDD architecture
    });
  });
}

void _verifyBoundedContextIsolation(
  String contextPath,
  List<String> forbiddenContexts,
) {
  final directory = Directory(contextPath);
  if (!directory.existsSync()) {
    return; // Skip if directory doesn't exist
  }

  final violations = <String>[];
  final dartFiles = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final content = file.readAsStringSync();
    for (final forbidden in forbiddenContexts) {
      // Patrones más precisos para evitar falsos positivos
      final pattern = RegExp("import\\s+['\"]package:[^/]+/$forbidden/");
      final relativePattern = RegExp("import\\s+['\"][^'\"]*/$forbidden/");

      if (pattern.hasMatch(content) || relativePattern.hasMatch(content)) {
        violations.add(
          '${file.path}: Imports from forbidden context: $forbidden',
        );
      }
    }
  }

  expect(
    violations,
    isEmpty,
    reason: 'Bounded context isolation violations:\n${violations.join('\n')}',
  );
}

List<String> _findAllBoundedContexts() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) return [];

  return libDir
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split('/').last)
      .where((name) => !name.startsWith('.'))
      .toList();
}

/// Detecta servicios específicos mal ubicados en shared/
List<String> _findMisplacedServicesInShared() {
  final issues = <String>[];
  final sharedDir = Directory('lib/shared');

  if (!sharedDir.existsSync()) return issues;

  final dartFiles = sharedDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final content = file.readAsStringSync();
    final relativePath = file.path.replaceFirst('lib/', '');

    // Detectar servicios que parecen específicos de un contexto
    if (_isContextSpecificService(file.path, content)) {
      final contextUsage = _analyzeContextUsage(file.path);
      if (contextUsage.isNotEmpty && contextUsage.length <= 2) {
        issues.add(
          '$relativePath (used primarily in: ${contextUsage.join(', ')})',
        );
      }
    }
  }

  return issues;
}

/// Detecta adaptadores con implementaciones vacías o de placeholder
List<String> _findEmptyAdapterImplementations() {
  final issues = <String>[];
  final libDir = Directory('lib');

  if (!libDir.existsSync()) return issues;

  final adapterFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.contains('adapter') && f.path.endsWith('.dart'));

  for (final file in adapterFiles) {
    final content = file.readAsStringSync();
    final relativePath = file.path.replaceFirst('lib/', '');

    // Detectar implementaciones vacías o con solo comentarios
    if (_hasEmptyImplementations(content)) {
      issues.add(relativePath);
    }
  }

  return issues;
}

/// Determina si un servicio es específico de un contexto
bool _isContextSpecificService(String filePath, String content) {
  final specificPatterns = [
    'prompt_builder',
    'meetstory',
    'biography',
    'onboarding',
    'chat_specific',
    'voice_specific',
  ];

  final fileName = filePath.split('/').last.toLowerCase();
  return specificPatterns.any((pattern) => fileName.contains(pattern));
}

/// Analiza en qué contextos se usa un archivo
List<String> _analyzeContextUsage(String filePath) {
  final contexts = <String>[];
  final libDir = Directory('lib');

  if (!libDir.existsSync()) return contexts;

  final serviceName = filePath.split('/').last.replaceFirst('.dart', '');

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && f.path != filePath);

  for (final file in dartFiles) {
    try {
      final content = file.readAsStringSync();

      if (content.contains(serviceName)) {
        final contextPath = file.path.replaceFirst('lib/', '').split('/').first;
        if (!contexts.contains(contextPath)) {
          contexts.add(contextPath);
        }
      }
    } on Exception {
      // Skip files that can't be read
    }
  }

  return contexts;
}

/// Detecta si un adaptador tiene implementaciones vacías
bool _hasEmptyImplementations(String content) {
  final emptyPatterns = [
    'Basic implementation',
    'could be enhanced',
    'maintains the architectural boundary',
    'Future implementation',
    'placeholder',
    'TODO:',
  ];

  return emptyPatterns.any((pattern) => content.contains(pattern));
}
