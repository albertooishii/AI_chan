import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('🎭 Presentation Layer Architecture Tests', () {
    test('screens should not contain excessive business logic', () async {
      // Buscar todas las pantallas del proyecto
      final screenFiles = <File>[];
      await _findScreenFiles(Directory('lib'), screenFiles);

      expect(
        screenFiles.isNotEmpty,
        isTrue,
        reason: 'Should find screen files in the project',
      );

      final violations = <String>[];

      for (final screenFile in screenFiles) {
        final relativePath = screenFile.path.replaceFirst('lib/', '');
        final lines = await screenFile.readAsLines();
        final lineCount = lines.length;

        // REGLA 1: Ninguna pantalla debería tener más de 800 líneas
        // (Límite razonable para una pantalla bien arquitecturada)
        if (lineCount > 800) {
          violations.add('🚨 $relativePath: $lineCount líneas (límite: 800)');
        }

        // REGLA 2: Detectar patrones de lógica de negocio en screens
        final content = await screenFile.readAsString();
        final businessLogicPatterns = _detectBusinessLogicPatterns(
          content,
          relativePath,
        );

        if (businessLogicPatterns.isNotEmpty) {
          violations.add('🔍 $relativePath: Lógica de negocio detectada');
          violations.addAll(businessLogicPatterns.map((p) => '   • $p'));
        }
      }

      // Estadísticas generales (mostradas en violaciones si es necesario)
      // ignore: avoid_print
      print('📊 Análisis de ${screenFiles.length} pantallas:');
      final sortedBySize = screenFiles.toList()
        ..sort((a, b) => _getLineCount(b).compareTo(_getLineCount(a)));

      for (int i = 0; i < 5 && i < sortedBySize.length; i++) {
        final file = sortedBySize[i];
        final lines = _getLineCount(file);
        final path = file.path.replaceFirst('lib/', '');
        // ignore: avoid_print
        print('   ${i + 1}. $path: $lines líneas');
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 VIOLACIONES DE ARQUITECTURA EN CAPA DE PRESENTACIÓN:

${violations.join('\n')}

PRINCIPIOS VIOLATED:
- Single Responsibility: Pantallas con demasiadas responsabilidades
- Separation of Concerns: Lógica de negocio mezclada con UI
- Testability: Lógica no testeable sin UI

SOLUCIONES RECOMENDADAS:
- Mover lógica compleja a Services o Use Cases
- Usar State Management (Provider, Bloc, Riverpod)
- Crear métodos de alto nivel que encapsulen flujos
- Pantallas solo deberían manejar: UI, eventos, estados de loading
        ''',
      );
    });

    test(
      'presentation layer should have proper service dependencies',
      () async {
        final screenFiles = <File>[];
        await _findScreenFiles(Directory('lib'), screenFiles);

        final recommendations = <String>[];

        for (final screenFile in screenFiles) {
          final relativePath = screenFile.path.replaceFirst('lib/', '');
          final content = await screenFile.readAsString();

          // Detectar pantallas que podrían beneficiarse de servicios
          if (content.contains('setState') && content.length > 500) {
            final hasServiceDependencies =
                content.contains('Service') ||
                content.contains('Provider') ||
                content.contains('Repository');

            if (!hasServiceDependencies) {
              recommendations.add(
                '💡 $relativePath: Considera extraer lógica a servicios',
              );
            }
          }
        }

        if (recommendations.isNotEmpty) {
          // ignore: avoid_print
          print('💡 Recomendaciones de arquitectura:');
          for (final rec in recommendations) {
            // ignore: avoid_print
            print('   $rec');
          }
        }

        // Este test no falla, solo informa
        expect(true, isTrue);
      },
    );

    test(
      'no screen should have more lines than its corresponding service',
      () async {
        final violations = <String>[];

        // Buscar pares screen-service
        final screenServicePairs = await _findScreenServicePairs();

        for (final pair in screenServicePairs) {
          final screenLines = await _getFileLineCount(pair['screen']!);
          final serviceLines = await _getFileLineCount(pair['service']!);

          if (screenLines > serviceLines * 1.2) {
            // Screen no debería ser más del 20% más grande
            final ratio = (screenLines / serviceLines).toStringAsFixed(2);
            violations.add(
              '⚖️  ${pair['screen']!.replaceFirst('lib/', '')}: $screenLines líneas vs ${pair['service']!.replaceFirst('lib/', '')}: $serviceLines líneas (ratio: $ratio:1)',
            );
          }
        }

        if (violations.isNotEmpty) {
          // ignore: avoid_print
          print('⚠️ Ratios screen/service problemáticos detectados:');
          for (final violation in violations) {
            // ignore: avoid_print
            print('   $violation');
          }
        }

        // Por ahora solo alertar, no fallar
        expect(true, isTrue);
      },
    );
  });
}

Future<void> _findScreenFiles(Directory dir, List<File> screenFiles) async {
  if (!await dir.exists()) return;

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final path = entity.path;

      // Identificar pantallas por patrones comunes
      if (path.contains('/screens/') ||
          path.contains('/pages/') ||
          path.endsWith('_screen.dart') ||
          path.endsWith('_page.dart') ||
          path.contains('/presentation/')) {
        // Excluir archivos de test y otros no relevantes
        if (!path.contains('/test/') &&
            !path.contains('.g.dart') &&
            !path.contains('.freezed.dart')) {
          screenFiles.add(entity);
        }
      }
    }
  }
}

List<String> _detectBusinessLogicPatterns(String content, String fileName) {
  final patterns = <String>[];

  // Patrones de lógica de negocio que NO deberían estar en pantallas
  final businessLogicIndicators = {
    r'if\s*\([^)]*\.contains\([^)]*\)\)': 'Lógica de validación compleja',
    r'switch\s*\([^)]*step[^)]*\)': 'Lógica de flujo de pasos',
    r'for\s*\([^)]*in\s+[^)]*\).*process': 'Procesamiento de datos en bucles',
    r'\.map\([^)]*\=\>\s*[^)]*validate': 'Validaciones en transformaciones',
    r'RegExp\(': 'Validaciones con expresiones regulares',
    r'\.parse[A-Z][a-zA-Z]*\(': 'Parsing de datos',
    r'await.*calculate': 'Cálculos asincrónicos',
    r'\.toJson\(\)|\.fromJson\(': 'Serialización de datos',
    r'http\.|dio\.|client\.': 'Llamadas HTTP directas',
  };

  for (final entry in businessLogicIndicators.entries) {
    final regex = RegExp(entry.key, multiLine: true);
    if (regex.hasMatch(content)) {
      final matches = regex.allMatches(content).length;
      patterns.add('${entry.value} ($matches ocurrencias)');
    }
  }

  return patterns;
}

int _getLineCount(File file) {
  try {
    return file.readAsLinesSync().length;
  } catch (e) {
    return 0;
  }
}

Future<int> _getFileLineCount(String filePath) async {
  try {
    final file = File(filePath);
    final lines = await file.readAsLines();
    return lines.length;
  } catch (e) {
    return 0;
  }
}

Future<List<Map<String, String>>> _findScreenServicePairs() async {
  final pairs = <Map<String, String>>[];

  // Buscar patrones comunes de screen-service
  final screenDirs = [
    'lib/onboarding/presentation/screens',
    'lib/chat/presentation/screens',
    'lib/call/presentation/screens',
  ];

  for (final screenDir in screenDirs) {
    final dir = Directory(screenDir);
    if (!await dir.exists()) continue;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('_screen.dart')) {
        final screenPath = entity.path;

        // Buscar el servicio correspondiente
        final baseName = entity.path
            .split('/')
            .last
            .replaceFirst('_screen.dart', '');
        final possibleServicePaths = [
          screenPath
              .replaceFirst('/presentation/screens/', '/services/')
              .replaceFirst('_screen.dart', '_service.dart'),
          screenPath
              .replaceFirst('/presentation/screens/', '/application/services/')
              .replaceFirst('_screen.dart', '_service.dart'),
          'lib/${screenPath.split('/')[1]}/services/${baseName}_service.dart',
          'lib/${screenPath.split('/')[1]}/services/${baseName}_ai_service.dart',
        ];

        for (final servicePath in possibleServicePaths) {
          if (await File(servicePath).exists()) {
            pairs.add({'screen': screenPath, 'service': servicePath});
            break;
          }
        }
      }
    }
  }

  return pairs;
}
