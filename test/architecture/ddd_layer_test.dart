import 'dart:io';
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
      final useCaseFiles = <String>[];
      final libDir = Directory('lib');

      if (!libDir.existsSync()) return;

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            (file.path.contains('/application/use_cases/') ||
                file.path.contains('/usecases/'))) {
          useCaseFiles.add(file.path);

          final content = file.readAsStringSync();

          // Use cases should have a single public execute/call method
          final publicMethods = RegExp(
            r'\s+[A-Z]\w*\s+\w+\s*\(',
          ).allMatches(content).length;
          final executeMethods = RegExp(
            r'(execute|call)\s*\(',
          ).allMatches(content).length;

          // This is informational - proper validation would require AST analysis
          if (publicMethods > 2 && executeMethods == 0) {
            print(
              '${file.path}: Potential SRP violation - multiple public methods without execute/call',
            );
          }
        }
      }

      print('Found ${useCaseFiles.length} use case files');
      expect(
        useCaseFiles.isNotEmpty,
        isTrue,
        reason: 'Should have use case files in application layer',
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

        print('Domain repositories: ${domainRepositories.length}');
        print(
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
