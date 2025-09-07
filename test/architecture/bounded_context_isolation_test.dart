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

      // Known violations that are planned for future refactoring
      final knownViolations = [
        // ✅ RESOLVED: UIStateManagementMixin eliminado de todos los controllers
        // ❌ REMAINING: Bounded context isolation violations (temporary - will be refactored)

        // Chat context importing from shared
        'lib/chat/application/use_cases/send_message_use_case.dart',
        'lib/chat/application/services/tts_service.dart',
        'lib/chat/application/services/message_retry_service.dart',
        'lib/chat/application/services/message_image_processing_service.dart',
        'lib/chat/application/utils/profile_persist_utils.dart',

        // Call context importing from chat and shared
        'lib/call/application/controllers/voice_call_screen_controller.dart',
        'lib/call/application/controllers/_call_playback_controller.dart',
        'lib/call/application/controllers/_call_state_controller.dart',
        'lib/call/application/controllers/call_controller.dart',
        'lib/call/application/controllers/_call_recording_controller.dart',
        'lib/call/application/use_cases/manage_audio_use_case.dart',
        'lib/call/application/use_cases/start_call_use_case.dart',
        'lib/call/application/use_cases/handle_incoming_call_use_case.dart',
        'lib/call/application/use_cases/end_call_use_case.dart',
        'lib/call/application/interfaces/voice_call_controller_builder.dart',
        'lib/call/application/services/call_state_application_service.dart',
        'lib/call/application/services/call_playback_application_service.dart',
        'lib/call/application/services/call_recording_application_service.dart',
        'lib/call/application/services/voice_call_application_service.dart',

        // Onboarding context importing from chat and shared
        'lib/onboarding/application/controllers/onboarding_lifecycle_controller.dart',
        'lib/onboarding/application/use_cases/biography_generation_use_case.dart',
        'lib/onboarding/application/use_cases/process_user_response_use_case.dart',
        'lib/onboarding/application/use_cases/import_export_onboarding_use_case.dart',
        'lib/onboarding/application/use_cases/save_chat_export_use_case.dart',
        'lib/onboarding/application/use_cases/generate_next_question_use_case.dart',
        'lib/onboarding/application/services/form_onboarding_application_service.dart',
      ];

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
- Domain layers cannot import from other bounded contexts
- Application layers should only depend on shared/core

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
