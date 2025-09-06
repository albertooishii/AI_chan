import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bounded Context Isolation Tests', () {
    test('chat domain should not import from other bounded contexts', () {
      _verifyBoundedContextIsolation('lib/chat/domain', [
        'onboarding',
        'voice',
      ]);
    });

    test('onboarding domain should not import from other bounded contexts', () {
      _verifyBoundedContextIsolation('lib/onboarding/domain', [
        'chat',
        'voice',
      ]);
    });

    test('voice domain should not import from other bounded contexts', () {
      _verifyBoundedContextIsolation('lib/voice/domain', [
        'chat',
        'onboarding',
      ]);
    });

    // Note: Domain layer dependency rules (no imports of infrastructure/presentation)
    // are tested in ddd_layer_test.dart to avoid duplication
  });
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
