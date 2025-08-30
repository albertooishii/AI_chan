import 'dart:io';
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

          // Look for concrete classes in domain layer that should be interfaces
          final concreteClassPattern = RegExp(r'class\s+(\w+)(?!\s+extends|\s+implements)');
          final matches = concreteClassPattern.allMatches(content);

          for (final match in matches) {
            final className = match.group(1)!;

            // Skip if it's already abstract
            if (content.contains('abstract class $className') ||
                content.contains('abstract interface class $className')) {
              continue;
            }

            // Check if it's a domain service, repository, or entity that should be abstract
            if ((className.endsWith('Service') || className.endsWith('Repository')) &&
                file.path.contains('/domain/interfaces/')) {
              violations.add('${file.path}: $className should be abstract interface (domain layer)');
            }

            // Check if it has only abstract/unimplemented methods (should be interface)
            final methodPattern = RegExp(r'\w+\s+\w+\s*\([^)]*\)\s*\{[^}]*\}');
            final implementedMethods = methodPattern.allMatches(content).length;
            final abstractMethods = RegExp(r'\w+\s+\w+\s*\([^)]*\);').allMatches(content).length;

            if (abstractMethods > 0 && implementedMethods == 0 && !content.contains('abstract')) {
              violations.add('${file.path}: $className has only abstract methods but is not marked as abstract');
            }
          }
        }
      }

      expect(violations, isEmpty, reason: 'Domain layer concrete class violations:\n${violations.join('\n')}');
    });

    test('adapters should implement domain interfaces', () {
      final violations = <String>[];
      final adapterFiles = <File>[];
      final domainInterfaces = <String>[];

      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      // Find adapter files and domain interfaces
      for (final file in libDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = file.readAsStringSync();

          // Find actual adapter implementations
          if (file.path.contains('/infrastructure/') && content.contains('implements') && content.contains('class')) {
            adapterFiles.add(file);
          }

          // Find domain interfaces (search in both /domain/ and /core/interfaces/)
          if (file.path.contains('/domain/interfaces/') ||
              file.path.contains('/core/interfaces/') ||
              (file.path.contains('/domain/') &&
                  (content.contains('abstract class') || content.contains('abstract interface')))) {
            final matches = RegExp(r'abstract (?:interface )?class\s+(\w+)').allMatches(content);
            for (final match in matches) {
              domainInterfaces.add(match.group(1)!);
            }
          }
        }
      }

      // Check that each adapter actually implements a domain interface
      for (final adapter in adapterFiles) {
        final content = adapter.readAsStringSync();
        final implementsPattern = RegExp(r'implements\s+(\w+)');
        final matches = implementsPattern.allMatches(content);

        bool implementsDomainInterface = false;
        for (final match in matches) {
          final implementedInterface = match.group(1)!;
          if (domainInterfaces.contains(implementedInterface)) {
            implementsDomainInterface = true;
            break;
          }
        }

        if (!implementsDomainInterface) {
          violations.add('${adapter.path}: Adapter does not implement any known domain interface');
        }
      }

      // Reasonable ratio check: too many adapters suggests over-engineering
      final ratio = adapterFiles.length / (domainInterfaces.isNotEmpty ? domainInterfaces.length : 1);
      if (ratio > 3.0) {
        violations.add(
          'Architecture concern: ${adapterFiles.length} adapters vs ${domainInterfaces.length} domain interfaces (${ratio.toStringAsFixed(1)}:1). Consider consolidation.',
        );
      }

      expect(violations, isEmpty, reason: 'Adapter implementation violations:\n${violations.join('\n')}');
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
