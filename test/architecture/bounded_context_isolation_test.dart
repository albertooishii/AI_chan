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

      // 🎉 Known violations - ALL RESOLVED! 100% COMPLETE! 🎉
      // Previously tracked bounded context isolation violations
      // Now all successfully resolved using Clean Architecture principles
      final knownViolations = <String>[
        // 🏆 ALL BOUNDED CONTEXT VIOLATIONS SUCCESSFULLY RESOLVED! 🏆
        // No remaining known violations - Perfect isolation achieved!
      ];

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

      // Verify application layer isolation (can import from shared/core)
      for (final context in boundedContexts) {
        final forbiddenContexts = boundedContexts
            .where((final c) => c != context && c != 'shared' && c != 'core')
            .toList();
        try {
          _verifyBoundedContextIsolation(
            'lib/$context/application',
            forbiddenContexts,
          );
        } on Exception catch (e) {
          // Filter out known violations
          final errorMessage = e.toString();
          final isKnownViolation = knownViolations.any(
            (final known) => errorMessage.contains(known),
          );

          if (!isKnownViolation) {
            violations.add('❌ $context application violates isolation: $e');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 BOUNDED CONTEXT ISOLATION VIOLATIONS (excluding known temporary violations):
${violations.join('\n')}

KNOWN TEMPORARY VIOLATIONS (planned for future refactoring):
${knownViolations.map((final v) => '• $v').join('\n')}

BOUNDED CONTEXTS MUST BE ISOLATED:
- Domain layers cannot import from other bounded contexts (shared/core allowed)
- Application layers can import from shared/core but not other bounded contexts
- Bounded contexts can only depend on shared/core for cross-cutting concerns

ALLOWED DEPENDENCIES:
✅ chat → shared/core
✅ call → shared/core  
✅ onboarding → shared/core

FORBIDDEN DEPENDENCIES:
❌ chat ↔ call
❌ chat ↔ onboarding  
❌ call ↔ onboarding

NOTE: The known violations above are temporary and will be addressed in future
refactoring to achieve full bounded context isolation. They are documented
here to allow the test suite to pass while maintaining current functionality.
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
