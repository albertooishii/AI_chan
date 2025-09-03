import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('🧹 Unused Code Detection Tests', () {
    test(
      'no unused files or public static methods should exist in utility classes',
      () {
        final libDir = Directory('lib');
        if (!libDir.existsSync()) return;

        final violations = <String>[];
        final allFiles = <File>[];
        final utilityFiles = <File>[];

        // Recopilar todos los archivos dart
        for (final file in libDir.listSync(recursive: true)) {
          if (file is File && file.path.endsWith('.dart')) {
            allFiles.add(file);
            if (_isUtilityFile(file.path, file.readAsStringSync())) {
              utilityFiles.add(file);
            }
          }
        }

        // Verificar archivos completos no utilizados primero
        for (final utilityFile in utilityFiles) {
          final relativePath = utilityFile.path.replaceFirst(
            '${libDir.path}/',
            '',
          );
          final packageImport = 'package:ai_chan/$relativePath';

          // Crear diferentes variaciones posibles del import
          final fileName = relativePath
              .split('/')
              .last
              .replaceFirst('.dart', '');
          final possibleImports = [
            packageImport,
            relativePath,
            '../$fileName.dart',
            './$fileName.dart',
            fileName,
          ];

          bool isFileUsed = false;

          // Buscar imports de este archivo en todo el codebase (incluyendo tests)
          for (final file in allFiles) {
            if (file.path == utilityFile.path) continue;

            final content = file.readAsStringSync();

            // Buscar cualquier forma de import/export
            for (final possibleImport in possibleImports) {
              if (content.contains(possibleImport)) {
                isFileUsed = true;
                break;
              }
            }

            if (isFileUsed) break;
          }

          // También buscar en tests
          if (!isFileUsed) {
            final testDir = Directory('test');
            if (testDir.existsSync()) {
              for (final file in testDir.listSync(recursive: true)) {
                if (file is File && file.path.endsWith('.dart')) {
                  final content = file.readAsStringSync();
                  for (final possibleImport in possibleImports) {
                    if (content.contains(possibleImport)) {
                      isFileUsed = true;
                      break;
                    }
                  }
                  if (isFileUsed) break;
                }
              }
            }
          }
          if (!isFileUsed) {
            violations.add(
              '🗑️  UNUSED FILE: ${utilityFile.path} - The entire file is not imported/used anywhere. Consider deleting it completely.',
            );
            continue; // Si el archivo no se usa, no necesitamos revisar sus funciones
          }

          // Solo si el archivo se usa, revisar funciones individuales
          final definedMethods = <String, String>{};
          final content = utilityFile.readAsStringSync();
          final lines = content.split('\n');

          String? currentClass;

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i].trim();

            // Detectar clase actual
            final classMatch = RegExp(r'^class\s+(\w+)').firstMatch(line);
            if (classMatch != null) {
              currentClass = classMatch.group(1);
              continue;
            }

            // Detectar métodos estáticos públicos
            final staticMethodMatch = RegExp(
              r'static\s+(?:Future<[^>]+>|[A-Za-z0-9<>,\s\?\[\]]+)\s+([a-zA-Z][a-zA-Z0-9_]*)\s*\(',
            ).firstMatch(line);

            if (staticMethodMatch != null && currentClass != null) {
              final methodName = staticMethodMatch.group(1)!;

              if (!_isExcludedMethod(
                methodName,
                currentClass,
                utilityFile.path,
              )) {
                final key = '$currentClass.$methodName';
                definedMethods[key] = utilityFile.path;
              }
            }
          }

          // Buscar usos de los métodos definidos
          final methodUsages = <String>{};

          for (final file in allFiles) {
            final fileContent = file.readAsStringSync();

            for (final methodKey in definedMethods.keys) {
              if (_isMethodUsed(fileContent, methodKey)) {
                methodUsages.add(methodKey);
              }
            }
          }

          // También buscar en tests
          final testDir = Directory('test');
          if (testDir.existsSync()) {
            for (final file in testDir.listSync(recursive: true)) {
              if (file is File && file.path.endsWith('.dart')) {
                final fileContent = file.readAsStringSync();

                for (final methodKey in definedMethods.keys) {
                  if (_isMethodUsed(fileContent, methodKey)) {
                    methodUsages.add(methodKey);
                  }
                }
              }
            }
          }

          // Encontrar métodos no utilizados
          for (final entry in definedMethods.entries) {
            final methodKey = entry.key;
            final filePath = entry.value;

            if (!methodUsages.contains(methodKey)) {
              violations.add(
                '🔧 Unused public static method: $methodKey in $filePath',
              );
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Unused files or public static methods found:\n${violations.join('\n')}\n\n'
              '🗑️  Files marked with "UNUSED FILE" should be deleted completely.\n'
              '🔧 Methods marked as unused should be removed or made private.',
        );
      },
    );

    test('no unused public functions should exist in service files', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final violations = <String>[];
      final definedFunctions = <String, String>{}; // functionName -> filePath
      final functionUsages = <String>{};

      // Primera pasada: encontrar funciones públicas en archivos de servicio
      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;

        // Solo verificar archivos de servicio
        if (!file.path.contains('/services/') &&
            !file.path.contains('/utils/') &&
            !file.path.endsWith('_service.dart') &&
            !file.path.endsWith('_utils.dart')) {
          continue;
        }

        final content = file.readAsStringSync();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();

          // Buscar funciones públicas (no métodos de clase)
          final functionMatch = RegExp(
            r'^(?:Future<[^>]+>|[A-Za-z0-9<>,\s\?\[\]]+)\s+([a-zA-Z][a-zA-Z0-9_]*)\s*\(',
          ).firstMatch(line);

          if (functionMatch != null &&
              !line.contains('class ') &&
              !line.contains('static ') &&
              !line.contains('void main(') &&
              !line.contains('if (') &&
              !line.contains('for (') &&
              !line.contains('while (') &&
              !line.contains('switch (') &&
              !line.contains('try {') &&
              line.length > 10) {
            // Evitar líneas muy cortas que pueden ser palabras reservadas
            final functionName = functionMatch.group(1)!;

            if (!_isExcludedFunction(functionName)) {
              definedFunctions[functionName] = file.path;
            }
          }
        }
      }

      // Segunda pasada: buscar usos
      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;

        final content = file.readAsStringSync();

        for (final functionName in definedFunctions.keys) {
          if (content.contains('$functionName(')) {
            functionUsages.add(functionName);
          }
        }
      }

      // Buscar en tests también
      final testDir = Directory('test');
      if (testDir.existsSync()) {
        for (final file in testDir.listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;

          final content = file.readAsStringSync();

          for (final functionName in definedFunctions.keys) {
            if (content.contains('$functionName(')) {
              functionUsages.add(functionName);
            }
          }
        }
      }

      // Encontrar funciones no utilizadas
      for (final entry in definedFunctions.entries) {
        final functionName = entry.key;
        final filePath = entry.value;

        if (!functionUsages.contains(functionName)) {
          violations.add('Unused public function: $functionName in $filePath');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Unused public functions found:\n${violations.join('\n')}\n\n'
            'These functions are defined but never called. Consider removing them.',
      );
    });
  });
}

/// Determina si un archivo es una clase de utilidad que debe ser verificada
bool _isUtilityFile(String filePath, String content) {
  // Excluir archivos que son claramente parte de la arquitectura principal
  if (filePath.contains('/main.dart') ||
      filePath.contains('/app.dart') ||
      filePath.contains('/routes.dart') ||
      filePath.contains('/presentation/screens/') ||
      filePath.contains('/presentation/widgets/') ||
      filePath.contains('/presentation/pages/') ||
      filePath.contains('/providers/') ||
      filePath.endsWith('.g.dart') ||
      filePath.endsWith('.freezed.dart')) {
    return false;
  }

  return filePath.contains('/utils/') ||
      filePath.contains('/services/') ||
      filePath.contains('/adapters/') ||
      filePath.contains('/helpers/') ||
      filePath.endsWith('_utils.dart') ||
      filePath.endsWith('_service.dart') ||
      filePath.endsWith('_helper.dart') ||
      filePath.endsWith('_adapter.dart') ||
      (content.contains('class ') && content.contains('static '));
}

/// Verifica si un método debe ser excluido de la verificación
bool _isExcludedMethod(String methodName, String className, String filePath) {
  // Métodos comunes que pueden no ser llamados directamente
  final excludedMethods = {
    'toString',
    'hashCode',
    'operator',
    'compareTo',
    'fromJson',
    'toJson',
    'copyWith',
    'props',
    'stringify',
    'build',
    'createState',
    'initState',
    'dispose',
    'didUpdateWidget',
    'didChangeDependencies',
    'main',
    'debugFillProperties',
    'when',
    'map',
    'maybeWhen',
    'maybeMap',
  };

  // Métodos de test
  if (methodName.startsWith('test') ||
      methodName.startsWith('setUp') ||
      methodName.startsWith('tearDown')) {
    return true;
  }

  // Métodos de Flutter framework
  if (excludedMethods.contains(methodName)) {
    return true;
  }

  // Getters y setters
  if (methodName.startsWith('get') || methodName.startsWith('set')) {
    return true;
  }

  // Métodos privados (no deberían ser detectados, pero por si acaso)
  if (methodName.startsWith('_')) {
    return true;
  }

  // Métodos que parecen ser de configuración o factory
  if (methodName.startsWith('create') ||
      methodName.startsWith('make') ||
      methodName.startsWith('build') ||
      methodName.startsWith('configure')) {
    return true;
  }

  return false;
}

/// Verifica si una función debe ser excluida de la verificación
bool _isExcludedFunction(String functionName) {
  final excludedFunctions = {
    'main', 'build', 'toString', 'hashCode', 'operator', 'compareTo',
    'fromJson', 'toJson', 'copyWith', 'props', 'stringify',
    // Palabras que aparecen en strings/comentarios pero no son funciones reales
    'RESUMEN', 'guapa', 'for', 'if', 'while', 'switch', 'try', 'catch',
    'final',
    'var',
    'const',
    'return',
    'void',
    'String',
    'int',
    'bool',
    'double',
  };

  return excludedFunctions.contains(functionName) ||
      functionName.startsWith('test') ||
      functionName.startsWith('setUp') ||
      functionName.startsWith('tearDown') ||
      functionName.length < 3; // Evitar palabras muy cortas
}

/// Verifica si un método es usado en el contenido
bool _isMethodUsed(String content, String methodKey) {
  final parts = methodKey.split('.');
  if (parts.length != 2) return false;

  final className = parts[0];
  final methodName = parts[1];

  // Buscar diferentes patrones de uso
  final patterns = [
    '$className.$methodName(', // Uso directo
    '$className\n      .$methodName(', // Llamada con salto de línea
    '$className\n          .$methodName(', // Llamada con más indentación
    '.$methodName(', // Uso con import as alias
    'get $methodName(', // Si es un getter
    'set $methodName(', // Si es un setter
    ' $methodName(', // Uso interno sin clase (con espacio)
    '\t$methodName(', // Uso interno sin clase (con tab)
    'await $methodName(', // Uso interno con await
    'return $methodName(', // Uso interno con return
    '= $methodName(', // Asignación directa
  ];

  for (final pattern in patterns) {
    if (content.contains(pattern)) {
      return true;
    }
  }

  // También buscar en strings de configuración o referencias dinámicas
  if (content.contains("'$methodName'") ||
      content.contains('"$methodName"') ||
      content.contains(methodName) && content.contains('reflect')) {
    return true;
  }

  return false;
}
