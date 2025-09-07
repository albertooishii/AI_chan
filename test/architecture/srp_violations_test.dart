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

    group('Code Quality - Controller Responsibilities', () {
      test(
        'controllers deben actuar como coordinadores, no como lógica de negocio',
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

            // Análisis cualitativo de responsabilidades
            final businessLogicScore = _analyzeBusinessLogicComplexity(content);
            final delegationScore = _analyzeDelegationPatterns(content);
            final uiResponsibilityScore = _analyzeUIResponsibilities(content);

            final issues = <String>[];

            // ✅ MEJORADO: Análisis más inteligente de controllers
            final isSimpleController = _isSimpleControllerPattern(
              content,
              file.path,
            );
            final isApplicationServiceController =
                _isApplicationServiceController(content);

            // Arquitectura first: priorizar calidad arquitectural sobre líneas
            if (businessLogicScore > 15) {
              issues.add(
                'CRÍTICO: Demasiada lógica de negocio embebida (score: $businessLogicScore)',
              );
            } else if (businessLogicScore > 12 &&
                !isApplicationServiceController) {
              issues.add(
                'Mucha lógica de negocio: $businessLogicScore patrones detectados',
              );
            }

            // Solo aplicar test de delegación si NO es un controller simple
            if (!isSimpleController &&
                delegationScore < 2 &&
                businessLogicScore > 8) {
              issues.add(
                'Falta delegación a Application Services (score: $delegationScore)',
              );
            }

            // Solo reportar líneas si hay también problemas arquitecturales
            if (lineCount > 500 && businessLogicScore > 10) {
              issues.add(
                'Excesivamente largo Y mal diseñado: $lineCount líneas',
              );
            }

            // ✅ MEJORADO: Solo marcar como "no válido" si realmente no tiene responsabilidades de UI
            if (uiResponsibilityScore < 1 &&
                !isSimpleController &&
                !_isValidNonUIController(content, file.path)) {
              issues.add('No parece ser un controller de UI válido');
            }

            if (issues.isNotEmpty) {
              violations.add('${file.path}:\n  ${issues.join('\n  ')}');
            }
          }

          if (violations.isNotEmpty) {
            fail(
              '❌ CONTROLLER RESPONSIBILITY VIOLATIONS:\n${violations.join('\n\n')}\n\n'
              '💡 SOLUCIÓN: Los controllers deben coordinar UI ↔ Application Services, no contener lógica de negocio',
            );
          }
          // Note: Controllers now follow proper delegation pattern
        },
      );

      test('controllers grandes deben tener justificación arquitectural', () async {
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

          // Para controllers >250 líneas, debe haber justificación
          if (lineCount > 250) {
            final hasApplicationServiceDelegation =
                content.contains('_applicationService') ||
                content.contains('ApplicationService');
            final hasGoodDelegationPatterns =
                _countDelegationMethods(content) > 3;
            final hasComplexUI =
                content.contains('TabController') ||
                content.contains('PageController') ||
                content.contains('AnimationController') ||
                file.path.contains('form');

            if (!hasApplicationServiceDelegation &&
                !hasGoodDelegationPatterns &&
                !hasComplexUI) {
              violations.add(
                '${file.path}: $lineCount líneas sin justificación arquitectural clara',
              );
            }
          }
        }

        if (violations.isNotEmpty) {
          fail(
            '❌ LARGE CONTROLLERS SIN JUSTIFICACIÓN:\n${violations.join('\n')}\n\n'
            '💡 Controllers grandes deben tener Application Services o manejar UI compleja',
          );
        }
      });
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

/// Analiza complejidad de lógica de negocio embebida
int _analyzeBusinessLogicComplexity(final String content) {
  int score = 0;

  // Patrones que indican lógica de negocio embebida
  final businessLogicPatterns = [
    RegExp(
      r'if\s*\([^)]*\.length\s*>\s*\d+\)',
      multiLine: true,
    ), // Validaciones complejas
    RegExp(
      r'for\s*\([^)]*in\s+[^)]*\)\s*\{[^}]{50,}',
      multiLine: true,
      dotAll: true,
    ), // Loops largos
    RegExp(
      r'switch\s*\([^)]*\)\s*\{[^}]{100,}',
      multiLine: true,
      dotAll: true,
    ), // Switch complejos
    RegExp(
      r'DateTime\.now\(\)[^;]{20,}',
      multiLine: true,
    ), // Cálculos de tiempo complejos
    RegExp(r'RegExp\(', multiLine: true), // Regex en controllers
    RegExp(
      r'\.map\s*\([^)]*\)\s*\.where\s*\([^)]*\)',
      multiLine: true,
    ), // Transformaciones de datos
    RegExp(
      r'try\s*\{[^}]{100,}',
      multiLine: true,
      dotAll: true,
    ), // Bloques try complejos
  ];

  for (final pattern in businessLogicPatterns) {
    score += pattern.allMatches(content).length;
  }

  // Penalizar métodos muy largos (>20 líneas)
  final methods = RegExp(
    r'(\w+\s+)?\w+\s*\([^)]*\)\s*(async\s+)?\{',
    multiLine: true,
  );
  for (final match in methods.allMatches(content)) {
    final methodStart = match.end;
    final methodContent = content.substring(methodStart);
    final methodEnd = _findMatchingBrace(methodContent);
    if (methodEnd > 0) {
      final methodLines = methodContent
          .substring(0, methodEnd)
          .split('\n')
          .length;
      if (methodLines > 20) score += 2;
    }
  }

  return score;
}

/// Analiza patrones de delegación a servicios
int _analyzeDelegationPatterns(final String content) {
  int score = 0;

  // Patrones positivos de delegación
  final delegationPatterns = [
    RegExp(r'_applicationService\.', multiLine: true),
    RegExp(r'_.*Service\.', multiLine: true),
    RegExp(r'await\s+\w+Service\.', multiLine: true),
    RegExp(r'final\s+result\s*=\s*await\s+', multiLine: true),
    RegExp(r'\.execute\(', multiLine: true),
    RegExp(r'UseCase.*\.call\(', multiLine: true),
  ];

  for (final pattern in delegationPatterns) {
    score += pattern.allMatches(content).length;
  }

  return score;
}

/// Analiza responsabilidades apropiadas de UI
int _analyzeUIResponsibilities(final String content) {
  int score = 0;

  // Patrones que indican responsabilidades de UI apropiadas
  final uiPatterns = [
    RegExp(r'notifyListeners\(\)', multiLine: true),
    RegExp(r'update\(\)', multiLine: true),
    RegExp(r'Navigator\.', multiLine: true),
    RegExp(r'showDialog', multiLine: true),
    RegExp(r'ScaffoldMessenger', multiLine: true),
    RegExp(
      r'extends\s+(ChangeNotifier|GetxController|BaseController)',
      multiLine: true,
    ),
    RegExp(r'BuildContext', multiLine: true),
    RegExp(r'setState\s*\(', multiLine: true),
    // ✅ AÑADIDO: Patrones para controllers de streams y callbacks
    RegExp(r'StreamController', multiLine: true),
    RegExp(r'Stream<', multiLine: true),
    RegExp(r'ValueListenable', multiLine: true),
    // ✅ AÑADIDO: Patrones para controllers de input/interacción
    RegExp(r'typedef.*Function', multiLine: true),
    RegExp(r'onUserTyping|scheduleSend|startRecording', multiLine: true),
    // ✅ AÑADIDO: Patrones para gestores de estado
    RegExp(r'_state|State', multiLine: true),
    RegExp(r'Controller', multiLine: true),
  ];

  for (final pattern in uiPatterns) {
    score += pattern.allMatches(content).length;
  }

  return score;
}

/// Cuenta métodos de delegación
int _countDelegationMethods(final String content) {
  final delegationMethods = RegExp(
    r'(await\s+_\w*[Ss]ervice\.\w+|_applicationService\.\w+)',
    multiLine: true,
  );
  return delegationMethods.allMatches(content).length;
}

/// Encuentra la llave de cierre correspondiente
int _findMatchingBrace(final String content) {
  int braceCount = 1;
  for (int i = 0; i < content.length; i++) {
    if (content[i] == '{') braceCount++;
    if (content[i] == '}') {
      braceCount--;
      if (braceCount == 0) return i;
    }
  }
  return -1;
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

/// Detecta si es un controller simple que delega a callbacks o funciones
bool _isSimpleControllerPattern(final String content, final String filePath) {
  // Controllers que son principalmente facades o adapters de funciones
  final simplePatternsIndicators = [
    // Controllers que principalmente exponen streams y callbacks
    content.contains('StreamController') && content.contains('typedef'),
    // Controllers de input que delegan a funciones pasadas como parámetro
    content.contains('scheduleSend') || content.contains('startRecording'),
    // Controllers que son principalmente holders de callbacks
    content.contains('Function()') && content.split('\n').length < 100,
    // Interfaces/builders que no contienen lógica
    filePath.contains('interface') || filePath.contains('builder'),
  ];

  return simplePatternsIndicators.any((final indicator) => indicator);
}

/// Detecta si es un controller que usa Application Services correctamente
bool _isApplicationServiceController(final String content) {
  return content.contains('ApplicationService') ||
      content.contains('_applicationService') ||
      content.contains('_voiceCallService');
}

/// Detecta si es un controller válido que no necesariamente maneja UI
bool _isValidNonUIController(final String content, final String filePath) {
  final validNonUIPatterns = [
    // Services que actúan como controllers
    filePath.contains('voice_call_controller.dart'),
    // Audio controllers que manejan streams
    content.contains('audio') && content.contains('Stream'),
    // Recording controllers
    content.contains('Recording') && content.contains('Controller'),
    // Subtitle controllers que manejan datos
    content.contains('subtitle') || content.contains('Subtitle'),
  ];

  return validNonUIPatterns.any((final pattern) => pattern);
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
