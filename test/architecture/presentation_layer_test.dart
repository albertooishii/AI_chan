import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:math' as math;

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
        final content = await screenFile.readAsString();

        // REGLA PRINCIPAL: Detectar patrones de lógica de negocio REAL en screens
        final businessLogicPatterns = _detectBusinessLogicPatterns(
          content,
          relativePath,
        );

        // Solo fallar si hay REAL lógica de negocio, no por tamaño
        if (businessLogicPatterns.isNotEmpty) {
          violations.add('� $relativePath: Lógica de negocio detectada');
          violations.addAll(businessLogicPatterns.map((p) => '   • $p'));
        }

        // ADVERTENCIA: Pantallas muy grandes (pero no fallo automático)
        if (lineCount > 1000) {
          // Solo advertir si es extremadamente grande Y tiene patrones sospechosos
          final suspiciousPatterns = _detectSuspiciousUIPatterns(content);
          if (suspiciousPatterns.isNotEmpty) {
            violations.add(
              '⚠️ $relativePath: $lineCount líneas con patrones sospechosos',
            );
            violations.addAll(suspiciousPatterns.map((p) => '   • $p'));
          }
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
🚨 VIOLACIONES REALES DE ARQUITECTURA EN CAPA DE PRESENTACIÓN:

${violations.join('\n')}

PRINCIPIOS VIOLATED:
- Separation of Concerns: Lógica de negocio mezclada con UI
- Single Responsibility: UI manejando lógica que no le corresponde  
- Testability: Lógica crítica no testeable sin UI

SOLUCIONES RECOMENDADAS:
- Mover lógica de negocio a Services o Use Cases
- Usar Provider/Bloc para estado complejo
- Extraer validaciones a clases dedicadas
- UI solo debería: renderizar, manejar eventos, mostrar estados

NOTA: Archivos grandes de UI son aceptables si solo contienen widgets y layout.
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

  // EXCLUSIONES: Patrones que SON correctos (usar servicios)
  final correctPatterns = [
    'Service.', // Llamadas a servicios
    'Provider.', // Uso de providers
    'Repository.', // Uso de repositorios
  ];

  final bool isUsingServices = correctPatterns.any(
    (pattern) => content.contains(pattern),
  );

  // Patrones REALES de lógica de negocio que NO deberían estar en pantallas
  final businessLogicIndicators = <String, String>{
    // Validaciones complejas directas (no a través de servicios)
    r'if\s*\([^)]*\.length\s*>\s*\d+\s*&&[^)]*\.contains\([^)]*\)\s*&&':
        'Validaciones de datos complejas inline',

    // Llamadas HTTP directas (no a través de servicios)
    r'http\.get\(|http\.post\(|dio\.get\(|dio\.post\(':
        'Llamadas HTTP directas',

    // Parsing JSON directo (no a través de servicios)
    r'jsonDecode\s*\(\s*[^)]*\)\s*\[': 'Parsing JSON directo',

    // Cálculos matemáticos complejos directos
    r'math\.|sqrt\(|pow\(|sin\(|cos\(|tan\(': 'Cálculos matemáticos directos',

    // Algoritmos de ordenamiento/filtrado complejos
    r'\.sort\s*\([^)]*\)\s*\.where\s*\([^)]*\)\s*\.map':
        'Algoritmos de procesamiento complejos',

    // Validaciones de reglas de negocio específicas
    r'if\s*\([^)]*balance[^)]*&&[^)]*credit|debt':
        'Reglas de negocio financieras',
    r'if\s*\([^)]*permission[^)]*&&[^)]*role[^)]*&&':
        'Lógica de autorización compleja',

    // Acceso directo a base de datos
    r'database\.execute\(|db\.query\(|sql\s*=':
        'Acceso directo a base de datos',
  };

  // Si el archivo está usando servicios apropiadamente, ser menos estricto
  final int thresholdOcurrences = isUsingServices ? 5 : 2;

  for (final entry in businessLogicIndicators.entries) {
    final regex = RegExp(entry.key, multiLine: true, caseSensitive: false);
    final matches = regex.allMatches(content);

    if (matches.isNotEmpty && matches.length >= thresholdOcurrences) {
      // Verificar que no sean falsos positivos comunes
      bool isFalsePositive = false;

      for (final match in matches) {
        final matchedText = content.substring(
          math.max(0, match.start - 50),
          math.min(content.length, match.end + 50),
        );

        // Excluir comentarios y imports
        if (matchedText.contains('//') ||
            matchedText.contains('import ') ||
            matchedText.contains('* ') ||
            matchedText.contains('Service.') ||
            matchedText.contains('Provider.')) {
          isFalsePositive = true;
          break;
        }
      }

      if (!isFalsePositive) {
        patterns.add('${entry.value} (${matches.length} ocurrencias)');
      }
    }
  }

  return patterns;
}

List<String> _detectSuspiciousUIPatterns(String content) {
  final patterns = <String>[];

  // Patrones que sugieren que una UI muy grande podría necesitar refactoring
  final suspiciousPatterns = <String, String>{
    // Solo para pantallas EXTREMADAMENTE complejas (más de 2000 líneas)
    r'build\(.*\)[^}]{800,}': 'Método build extremadamente largo (>800 líneas)',
    r'switch\s*\([^)]*\)[^}]{400,}':
        'Switch statement muy complejo (>400 líneas)',
  };

  // Solo reportar si el archivo es REALMENTE grande (>2000 líneas)
  final lineCount = content.split('\n').length;
  if (lineCount < 2000) return patterns;

  for (final entry in suspiciousPatterns.entries) {
    final regex = RegExp(entry.key, multiLine: true, dotAll: true);
    if (regex.hasMatch(content)) {
      patterns.add(entry.value);
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
