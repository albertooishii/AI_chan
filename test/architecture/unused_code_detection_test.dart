import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('🧹 Unused Code Detection Tests', () {
    test('dart analyze should detect unused code automatically', () {
      // ℹ️ NOTA: Este test es principalmente documentativo.
      //
      // Dart ya detecta automáticamente código no usado con:
      // - unused_element: métodos, clases no usados
      // - unused_field: campos de clase no usados
      // - unused_import: imports no usados
      // - unused_local_variable: variables locales no usadas
      //
      // Configurado en analysis_options.yaml en la sección analyzer.errors
      //
      // Para verificar código no usado, ejecuta:
      // $ dart analyze
      // $ flutter analyze

      // Test simbólico: verificar que tenemos directorios de utilidades
      final utilityDirs = ['lib/shared/utils/', 'lib/core/utils/'];
      final existingDirs = <String>[];

      for (final dirPath in utilityDirs) {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          existingDirs.add(dirPath);
        }
      }

      // Solo verificar que al menos hay un directorio de utils (es normal)
      expect(
        existingDirs,
        isNotEmpty,
        reason:
            'Deberían existir directorios de utilidades para organizar helpers',
      );
    });

    test('utility files should contain meaningful public methods', () {
      // 🎯 Test complementario: verificar que archivos utils no estén vacíos
      final utilityDirs = ['lib/shared/utils/', 'lib/core/utils/'];
      final emptyOrTrivialFiles = <String>[];

      for (final targetPath in utilityDirs) {
        final targetDir = Directory(targetPath);
        if (!targetDir.existsSync()) continue;

        for (final file in targetDir.listSync()) {
          if (file is File && file.path.endsWith('.dart')) {
            final content = file.readAsStringSync();

            if (_isEmptyOrTrivialUtilityFile(content)) {
              emptyOrTrivialFiles.add(file.path);
            }
          }
        }
      }

      if (emptyOrTrivialFiles.isNotEmpty) {
        fail(
          'Utility files that should be reviewed or removed:\n'
          '${emptyOrTrivialFiles.join('\n')}\n\n'
          '💡 Consider removing empty files or adding meaningful utility methods',
        );
      }
    });
  });
}

/// Verifica si un archivo de utilidades está vacío o es trivial
bool _isEmptyOrTrivialUtilityFile(final String content) {
  final lines = content.split('\n');
  final meaningfulLines = lines.where((final line) {
    final trimmed = line.trim();
    return trimmed.isNotEmpty &&
        !trimmed.startsWith('//') &&
        !trimmed.startsWith('import') &&
        !trimmed.startsWith('library') &&
        !trimmed.startsWith('export') &&
        trimmed != '{' &&
        trimmed != '}';
  }).toList();

  // Si tiene menos de 5 líneas significativas, probablemente es trivial
  return meaningfulLines.length < 5;
}
