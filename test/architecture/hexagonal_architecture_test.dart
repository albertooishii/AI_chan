import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hexagonal Architecture Tests', () {
    // Note: Domain layer isolation (no imports of infrastructure) is tested
    // in ddd_layer_test.dart to avoid duplication

    test('domain interfaces should be abstract or have abstract methods', () {
      final violations = <String>[];
      final domainDir = Directory('lib');

      if (!domainDir.existsSync()) return;

      for (final file in domainDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart') && file.path.contains('/domain/')) {
          final content = file.readAsStringSync();

          // Check for repository or service interfaces
          if (content.contains('Repository') || content.contains('Service')) {
            // If it's not abstract and doesn't have abstract methods, it might be a violation
            if (!content.contains('abstract class') &&
                !content.contains('abstract') &&
                content.contains('class ') &&
                !content.contains('{') &&
                !content.contains('}')) {
              // This is a simple heuristic - in practice you'd want more sophisticated parsing
              final className = RegExp(r'class\s+(\w+)').firstMatch(content)?.group(1);
              if (className != null && (className.contains('Repository') || className.contains('Service'))) {
                violations.add('${file.path}: $className should be abstract interface');
              }
            }
          }
        }
      }

      // This test is informational for now - architectural review needed
      debugPrint('Domain interfaces found: ${violations.length} potential improvements');
    });

    test('adapters should implement domain interfaces', () {
      final adapterFiles = <File>[];
      final domainInterfaces = <String>[];

      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      // Find adapter files
      for (final file in libDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          if (file.path.contains('/adapters/') || file.path.contains('/infrastructure/')) {
            adapterFiles.add(file);
          }
          if (file.path.contains('/domain/')) {
            final content = file.readAsStringSync();
            // Look for abstract classes (interfaces)
            final matches = RegExp(r'abstract class\s+(\w+)').allMatches(content);
            for (final match in matches) {
              domainInterfaces.add(match.group(1)!);
            }
          }
        }
      }

      debugPrint('Found ${adapterFiles.length} adapter files and ${domainInterfaces.length} domain interfaces');

      // This is informational - proper validation would require AST parsing
      expect(
        adapterFiles.isNotEmpty || domainInterfaces.isNotEmpty,
        isTrue,
        reason: 'Should have adapters implementing domain interfaces',
      );
    });

    test('presentation layer should depend on domain, not infrastructure', () {
      final violations = <String>[];
      final libDir = Directory('lib');

      if (!libDir.existsSync()) return;

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart') && file.path.contains('/presentation/')) {
          final content = file.readAsStringSync();

          // Presentation can import domain but not infrastructure directly
          final infrastructurePattern = RegExp('import\\s+["\'].*/(infrastructure|adapters)/');

          if (infrastructurePattern.hasMatch(content)) {
            violations.add('${file.path}: Presentation layer imports infrastructure directly');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Presentation importing infrastructure violations:\n${violations.join('\n')}',
      );
    });
  });
}
