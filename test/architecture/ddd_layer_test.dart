import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DDD Layer Architecture Tests', () {
    test('application layer should only depend on domain layer', () {
      final violations = <String>[];
      final libDir = Directory('lib');

      if (!libDir.existsSync()) return;

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.path.contains('/application/')) {
          final content = file.readAsStringSync();

          // Application can import domain but not infrastructure or presentation
          final forbiddenPatterns = [
            RegExp('import\\s+["\'].*/(infrastructure|presentation)/'),
            RegExp('import\\s+["\']package:ai_chan/.*/infrastructure/'),
            RegExp('import\\s+["\']package:ai_chan/.*/presentation/'),
          ];

          for (final pattern in forbiddenPatterns) {
            if (pattern.hasMatch(content)) {
              violations.add(
                '${file.path}: Application layer has forbidden dependency',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Application layer dependency violations:\n${violations.join('\n')}',
      );
    });

    test('domain entities should not have external dependencies', () {
      final violations = <String>[];
      final libDir = Directory('lib');

      if (!libDir.existsSync()) return;

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            (file.path.contains('/domain/entities/') ||
                file.path.contains('/domain/value_objects/'))) {
          final content = file.readAsStringSync();

          // Entities should not import framework or external dependencies
          final forbiddenPatterns = [
            RegExp('import\\s+["\']package:flutter/'),
            RegExp('import\\s+["\']package:http/'),
            RegExp('import\\s+["\']package:dio/'),
            RegExp('import\\s+["\']package:shared_preferences/'),
            RegExp('import\\s+["\']dart:io'),
          ];

          for (final pattern in forbiddenPatterns) {
            if (pattern.hasMatch(content)) {
              violations.add(
                '${file.path}: Domain entity has external dependency',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Domain entity dependency violations:\n${violations.join('\n')}',
      );
    });

    test('use cases should follow single responsibility principle', () {
      final violations = <String>[];
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.path.contains('/use_case')) {
          final content = file.readAsStringSync();

          // Count methods (simplified heuristic) - exclude constructors and throws
          final methodMatches = RegExp(
            r'^\s+(?:Future<[^>]+>|[A-Z][a-zA-Z0-9<>]*)\s+([a-z]\w*)\s*\([^)]*\)\s*(?:async\s*)?\{',
            multiLine: true,
          );
          final publicMethods = methodMatches.allMatches(content).length;

          // Check if main method is too long (> 100 lines is a red flag)
          final lines = content.split('\n');
          bool inMethod = false;
          int methodLines = 0;
          int maxMethodLength = 0;

          for (final line in lines) {
            if (line.contains('async {') || line.contains(') {')) {
              inMethod = true;
              methodLines = 0;
            } else if (inMethod && line.trim() == '}') {
              inMethod = false;
              if (methodLines > maxMethodLength) {
                maxMethodLength = methodLines;
              }
            } else if (inMethod) {
              methodLines++;
            }
          }

          // Flag potential SRP violations
          if (maxMethodLength > 100) {
            violations.add(
              '${file.path}: Method too long ($maxMethodLength lines) - potential SRP violation',
            );
          }

          if (publicMethods > 6) {
            violations.add(
              '${file.path}: Too many public methods ($publicMethods) - should focus on single responsibility',
            );
          }

          // Check for multiple distinct responsibilities in one use case
          final responsibilities = <String>[];

          // Only count as responsibility if NOT delegated to service
          bool hasService(String servicePattern) {
            return content.contains(servicePattern) ||
                content.contains('Service');
          }

          if ((content.contains('validation') ||
                  content.contains('validate')) &&
              !hasService('ValidationsService')) {
            responsibilities.add('validation');
          }
          if ((content.contains('retry') || content.contains('attempt')) &&
              !hasService('RetryService')) {
            responsibilities.add('retry-logic');
          }
          if ((content.contains('image') && content.contains('save')) &&
              !hasService('ImageService')) {
            responsibilities.add('image-processing');
          }
          if ((content.contains('audio') || content.contains('tts')) &&
              !hasService('AudioService')) {
            responsibilities.add('audio-processing');
          }
          if ((content.contains('event') && content.contains('timeline')) &&
              !hasService('EventService')) {
            responsibilities.add('event-processing');
          }
          if ((content.contains('sanitize') || content.contains('clean')) &&
              !hasService('SanitizationService')) {
            responsibilities.add('sanitization');
          }

          if (responsibilities.length > 2) {
            violations.add(
              '${file.path}: Multiple responsibilities detected: ${responsibilities.join(', ')}',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Single Responsibility Principle violations detected:\n${violations.join('\n')}',
      );
    });

    test(
      'repositories should be in domain and implemented in infrastructure',
      () {
        final domainRepositories = <String>[];
        final infrastructureRepositories = <String>[];
        final libDir = Directory('lib');

        if (!libDir.existsSync()) return;

        for (final file in libDir.listSync(recursive: true)) {
          if (file is File &&
              file.path.endsWith('.dart') &&
              file.path.contains('repository')) {
            if (file.path.contains('/domain/')) {
              domainRepositories.add(file.path);
            } else if (file.path.contains('/infrastructure/') ||
                file.path.contains('/adapters/')) {
              infrastructureRepositories.add(file.path);
            }
          }
        }

        debugPrint('Domain repositories: ${domainRepositories.length}');
        debugPrint(
          'Infrastructure repositories: ${infrastructureRepositories.length}',
        );

        // Both should exist for proper DDD
        expect(
          domainRepositories.isNotEmpty,
          isTrue,
          reason: 'Should have repository interfaces in domain layer',
        );
      },
    );

    test('value objects should be immutable', () {
      final violations = <String>[];
      final libDir = Directory('lib');

      if (!libDir.existsSync()) return;

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.path.contains('/domain/value_objects/')) {
          final content = file.readAsStringSync();

          // Value objects should not have setters
          if (content.contains('set ') && !content.contains('// ignore:')) {
            violations.add(
              '${file.path}: Value object has setter (should be immutable)',
            );
          }

          // Should have final fields
          final finalFields = RegExp(r'final\s+\w+').allMatches(content).length;
          final varFields = RegExp(
            r'(?<!final\s)\b\w+\s+\w+\s*;',
          ).allMatches(content).length;

          if (varFields > finalFields && content.contains('class ')) {
            violations.add(
              '${file.path}: Value object should use final fields',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Value object immutability violations:\n${violations.join('\n')}',
      );
    });
  });
}
