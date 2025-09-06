import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('Single Responsibility Principle (SRP) - Architecture Tests', () {
    group('Application Layer - Controller Complexity', () {
      test('controllers no deben tener más de 3 use cases inyectados', () async {
        final violations = <String>[];

        // Buscar todos los controllers
        final controllersDir = Directory('lib');
        final controllerFiles = await controllersDir
            .list(recursive: true)
            .where((final entity) => entity is File)
            .cast<File>()
            .where(
              (final file) =>
                  file.path.contains('controller') &&
                  file.path.endsWith('.dart'),
            )
            .toList();

        for (final file in controllerFiles) {
          final content = await file.readAsString();
          final useCaseCount = _countUseCaseInjections(content);

          if (useCaseCount > 3) {
            violations.add(
              '${file.path}: $useCaseCount use cases inyectados (máximo: 3)',
            );
          }
        }

        if (violations.isNotEmpty) {
          fail(
            '❌ SRP VIOLATIONS - Controllers con demasiados use cases:\n${violations.join('\n')}\n\n'
            '💡 SOLUCIÓN: Crear Application Service que coordine estos use cases',
          );
        }
      });

      test(
        'controllers no deben tener más de 5 dependencias inyectadas',
        () async {
          final violations = <String>[];

          final controllersDir = Directory('lib');
          final controllerFiles = await controllersDir
              .list(recursive: true)
              .where((final entity) => entity is File)
              .cast<File>()
              .where(
                (final file) =>
                    file.path.contains('controller') &&
                    file.path.endsWith('.dart'),
              )
              .toList();

          for (final file in controllerFiles) {
            final content = await file.readAsString();
            final dependencyCount = _countConstructorDependencies(content);

            if (dependencyCount > 5) {
              violations.add(
                '${file.path}: $dependencyCount dependencias (máximo: 5)',
              );
            }
          }

          if (violations.isNotEmpty) {
            fail(
              '❌ SRP VIOLATIONS - Controllers con demasiadas dependencias:\n${violations.join('\n')}\n\n'
              '💡 SOLUCIÓN: Crear Application Service como Facade pattern',
            );
          }
        },
      );
    });

    group('Application Layer - Missing Application Services', () {
      test('módulos DDD deben tener Application Service coordinador', () {
        final violations = <String>[];

        // Verificar módulos que deben tener Application Service
        final requiredModules = ['call', 'onboarding'];

        for (final module in requiredModules) {
          final serviceFile = File(
            'lib/$module/application/services/${module}_application_service.dart',
          );
          if (!serviceFile.existsSync()) {
            violations.add('❌ Falta: ${serviceFile.path}');

            // Verificar si tiene muchos use cases sin coordinador
            final useCasesDir = Directory('lib/$module/application/use_cases');
            if (useCasesDir.existsSync()) {
              final useCaseCount = useCasesDir.listSync().length;
              if (useCaseCount > 2) {
                violations.add(
                  '   📊 $module tiene $useCaseCount use cases sin coordinador',
                );
              }
            }
          }
        }

        if (violations.isNotEmpty) {
          fail(
            '❌ SRP VIOLATIONS - Módulos sin Application Service coordinador:\n${violations.join('\n')}\n\n'
            '💡 SOLUCIÓN: Crear Application Services faltantes para coordinar use cases',
          );
        }
      });

      test('use cases no deben tener estado estático compartido', () async {
        final violations = <String>[];

        final useCasesDir = Directory('lib');
        final useCaseFiles = await useCasesDir
            .list(recursive: true)
            .where((final entity) => entity is File)
            .cast<File>()
            .where(
              (final file) =>
                  file.path.contains('use_case') && file.path.endsWith('.dart'),
            )
            .toList();

        for (final file in useCaseFiles) {
          final content = await file.readAsString();

          // Detectar estado estático (violación de SRP)
          if (content.contains(RegExp(r'static\s+.*List.*=')) ||
              content.contains(RegExp(r'static\s+.*Map.*=')) ||
              content.contains(RegExp(r'static\s+final.*=.*\[\]')) ||
              content.contains(RegExp(r'static\s+final.*=.*\{\}'))) {
            violations.add('${file.path}: Contiene estado estático compartido');
          }
        }

        if (violations.isNotEmpty) {
          fail(
            '❌ SRP VIOLATIONS - Use Cases con estado estático:\n${violations.join('\n')}\n\n'
            '💡 SOLUCIÓN: Mover estado a Application Service con inyección de dependencias',
          );
        }
      });
    });

    group('Architecture - Dependency Direction', () {
      test(
        'controllers no deben importar directamente use cases de otros módulos',
        () async {
          final violations = <String>[];

          final controllersDir = Directory('lib');
          final controllerFiles = await controllersDir
              .list(recursive: true)
              .where((final entity) => entity is File)
              .cast<File>()
              .where(
                (final file) =>
                    file.path.contains('controller') &&
                    file.path.endsWith('.dart'),
              )
              .toList();

          for (final file in controllerFiles) {
            final content = await file.readAsString();
            final currentModule = _extractModuleName(file.path);

            // Detectar imports cross-module
            final crossModuleImports = _findCrossModuleUseCaseImports(
              content,
              currentModule,
            );
            if (crossModuleImports.isNotEmpty) {
              violations.add(
                '${file.path}: Imports cross-module: ${crossModuleImports.join(', ')}',
              );
            }
          }

          if (violations.isNotEmpty) {
            fail(
              '❌ SRP VIOLATIONS - Controllers con dependencias cross-module:\n${violations.join('\n')}\n\n'
              '💡 SOLUCIÓN: Usar Application Services como boundaries entre módulos',
            );
          }
        },
      );
    });

    group('Code Metrics - Complexity', () {
      test(
        'controllers no deben superar 200 líneas (alta complejidad)',
        () async {
          final violations = <String>[];

          final controllersDir = Directory('lib');
          final controllerFiles = await controllersDir
              .list(recursive: true)
              .where((final entity) => entity is File)
              .cast<File>()
              .where(
                (final file) =>
                    file.path.contains('controller') &&
                    file.path.endsWith('.dart'),
              )
              .toList();

          for (final file in controllerFiles) {
            final content = await file.readAsString();
            final lineCount = content.split('\n').length;

            if (lineCount > 200) {
              violations.add(
                '${file.path}: $lineCount líneas (máximo recomendado: 200)',
              );
            }
          }

          if (violations.isNotEmpty) {
            fail(
              '❌ SRP VIOLATIONS - Controllers muy complejos:\n${violations.join('\n')}\n\n'
              '💡 SOLUCIÓN: Extraer lógica a Application Services',
            );
          }
        },
      );
    });
  });
}

/// Cuenta cuántos use cases están inyectados en el constructor
int _countUseCaseInjections(final String content) {
  final useCasePattern = RegExp(r'UseCase\s+\w+', multiLine: true);
  return useCasePattern.allMatches(content).length;
}

/// Cuenta dependencias en el constructor
int _countConstructorDependencies(final String content) {
  // Buscar parámetros required en constructor
  final constructorMatch = RegExp(
    r'(\w+)\s*\(\s*\{([^}]+)\}',
    multiLine: true,
    dotAll: true,
  ).firstMatch(content);

  if (constructorMatch == null) return 0;

  final params = constructorMatch.group(2) ?? '';
  final requiredParams = RegExp(r'required\s+\w+').allMatches(params);
  return requiredParams.length;
}

/// Extrae el nombre del módulo del path
String _extractModuleName(final String filePath) {
  final parts = filePath.split('/');
  final libIndex = parts.indexOf('lib');
  if (libIndex >= 0 && libIndex + 1 < parts.length) {
    return parts[libIndex + 1];
  }
  return '';
}

/// Encuentra imports de use cases de otros módulos
List<String> _findCrossModuleUseCaseImports(
  final String content,
  final String currentModule,
) {
  final violations = <String>[];
  final importPattern = RegExp(
    r"import\s+'package:ai_chan/(\w+)/.*use_case.*'",
    multiLine: true,
  );

  for (final match in importPattern.allMatches(content)) {
    final importedModule = match.group(1);
    if (importedModule != null &&
        importedModule != currentModule &&
        importedModule != 'shared') {
      violations.add('$importedModule use case');
    }
  }

  return violations;
}
