import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('File location rules', () {
    test('no layer folders nested inside domain/infrastructure/presentation', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final files = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

      final violations = <String>[];

      // Forbidden nesting patterns: e.g. domain/.../infrastructure
      final forbiddenPatterns = <RegExp, String>{
        RegExp(r'/domain/.*/(infrastructure|adapters|presentation)/'):
            'No debe haber carpetas de infraestructura/adapters/presentation dentro de domain',
        RegExp(r'/(infrastructure|adapters)/.*/(domain|presentation)/'):
            'No debe haber carpetas de domain/presentation dentro de infrastructure/adapters',
        RegExp(r'/presentation/.*/(domain|infrastructure|adapters)/'):
            'No debe haber carpetas de domain/infrastructure/adapters dentro de presentation',
      };

      for (final f in files) {
        final path = f.path.replaceAll('\\', '/');
        for (final entry in forbiddenPatterns.entries) {
          if (entry.key.hasMatch(path)) {
            violations.add('$path -> ${entry.value}');
          }
        }
      }

      expect(violations, isEmpty, reason: 'Reglas de ubicación violadas:\n${violations.join('\n')}');
    });

    test('no files with forbidden suffixes or generated files in source folders', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final files = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

      final violations = <String>[];

      for (final f in files) {
        final path = f.path.replaceAll('\\', '/');

        // Example rule: generated files (.g.dart) should live only next to sources,
        // but decide to flag any unexpected generated file under domain as example
        if (path.contains('/domain/') && path.endsWith('.g.dart')) {
          violations.add('$path -> Archivo generado dentro de domain (revisa ubicación)');
        }

        // Example extra rule: don't commit build artefacts into lib
        if (path.contains('/build/') || path.contains('/.dart_tool/')) {
          violations.add('$path -> Artefacto de build presente dentro de lib');
        }
      }

      expect(violations, isEmpty, reason: 'Archivos en ubicaciones prohibidas:\n${violations.join('\n')}');
    });
  });
}
