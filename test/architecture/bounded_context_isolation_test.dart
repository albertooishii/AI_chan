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

      // Verify each context doesn't import from others
      for (final context in boundedContexts) {
        final otherContexts = boundedContexts
            .where((final c) => c != context)
            .toList();
        try {
          _verifyBoundedContextIsolation('lib/$context/domain', otherContexts);
        } on Exception catch (e) {
          violations.add('❌ $context domain violates isolation: $e');
        }
      }

      // Verify application layer isolation
      for (final context in boundedContexts) {
        final otherContexts = boundedContexts
            .where((final c) => c != context)
            .toList();
        try {
          _verifyBoundedContextIsolation(
            'lib/$context/application',
            otherContexts,
          );
        } on Exception catch (e) {
          violations.add('❌ $context application violates isolation: $e');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 BOUNDED CONTEXT ISOLATION VIOLATIONS:
${violations.join('\n')}

BOUNDED CONTEXTS MUST BE ISOLATED:
- Domain layers cannot import from other bounded contexts
- Application layers should only depend on shared/core
        ''',
      );
    });

    // Note: Domain layer dependency rules (no imports of infrastructure/presentation)
    // are tested in clean_ddd_architecture_test.dart to avoid duplication
  });
}

List<String> _findAllBoundedContexts() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) return [];

  return libDir
      .listSync()
      .whereType<Directory>()
      .map((final d) => d.path.split('/').last)
      .where(
        (final name) =>
            !name.startsWith('.') &&
            name != 'core' &&
            name != 'main.dart' &&
            Directory('lib/$name/domain').existsSync(),
      )
      .toList();
}

void _verifyBoundedContextIsolation(
  final String contextPath,
  final List<String> forbiddenContexts,
) {
  final dir = Directory(contextPath);
  if (!dir.existsSync()) return;

  final violations = <String>[];

  for (final file in dir.listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      final content = file.readAsStringSync();

      for (final forbidden in forbiddenContexts) {
        // Check for relative imports
        final pattern = RegExp('import\\s+["\'].*/$forbidden/');
        // Check for package imports
        final packagePattern = RegExp(
          'import\\s+["\']package:ai_chan/$forbidden/',
        );

        if (pattern.hasMatch(content) || packagePattern.hasMatch(content)) {
          violations.add(
            '${file.path}: Imports from forbidden context: $forbidden',
          );
        }
      }
    }
  }

  expect(
    violations,
    isEmpty,
    reason: 'Bounded context isolation violations:\n${violations.join('\n')}',
  );
}
