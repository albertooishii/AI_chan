import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CQRS Separation Tests', () {
    test(
      'Queries should not mutate state (no repository.save/insert/update/delete)',
      () {
        final violations = <String>[];
        final libDir = Directory('lib');
        if (!libDir.existsSync()) return;

        // Heurística: archivos en carpetas named queries/ o que contienen QueryHandler/Query
        final queryFiles = <File>[];

        for (final ent in libDir.listSync(recursive: true)) {
          if (ent is! File) continue;
          final path = ent.path.replaceAll(r'\\', '/');
          if (!path.endsWith('.dart')) continue;

          final lower = path.toLowerCase();
          if (lower.contains('/queries/') ||
              lower.contains('query') ||
              lower.contains('query_handler')) {
            queryFiles.add(ent);
          }
        }

        // Common write patterns that should not appear in queries
        final writePatterns = [
          'save(',
          'insert(',
          'update(',
          'delete(',
          'remove(',
          '.addAll(',
          'repository.save',
          'repository.insert',
          'repository.update',
          'repository.delete',
        ];

        for (final file in queryFiles) {
          final content = file.readAsStringSync();
          for (final pattern in writePatterns) {
            if (content.contains(pattern)) {
              violations.add(
                '${file.path}: Query-like file contains write pattern: $pattern',
              );
            }
          }
        }

        // Additional heuristic: files named *Query* that contain 'await repository.' followed by write verbs
        final repoWriteRegex = RegExp(
          r'await\s+\w+\.(save|insert|update|delete)\s*\(',
        );
        for (final file in queryFiles) {
          final content = file.readAsStringSync();
          if (repoWriteRegex.hasMatch(content)) {
            violations.add(
              '${file.path}: Query contains awaited repository write operation',
            );
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'CQRS VIOLATIONS: Query handlers/files should not mutate state.\n${violations.join('\n')}',
        );
      },
    );

    test('Commands should perform or delegate writes (sanity check)', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final commandFiles = <File>[];
      for (final ent in libDir.listSync(recursive: true)) {
        if (ent is! File) continue;
        final path = ent.path.replaceAll(r'\\', '/');
        if (!path.endsWith('.dart')) continue;
        final lower = path.toLowerCase();
        if (lower.contains('/commands/') ||
            lower.contains('command_handler') ||
            lower.contains('command')) {
          commandFiles.add(ent);
        }
      }

      final writePatterns = RegExp(
        r'save\(|insert\(|update\(|delete\(|repository\.(save|insert|update|delete)',
      );
      final warnings = <String>[];

      for (final file in commandFiles) {
        final content = file.readAsStringSync();
        if (!writePatterns.hasMatch(content)) {
          warnings.add(
            '${file.path}: Command-like file contains no obvious write operations (may be OK, review manually)',
          );
        }
      }

      // Do not fail the build for commands lacking writes, only warn via expect with clear message when there are many
      expect(
        warnings.length < 50,
        isTrue,
        reason:
            'CQRS SANITY: Many command files without detectable writes. Sample:\n${warnings.take(10).join('\n')}',
      );
    });
  });
}
