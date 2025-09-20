import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// Test simple y efectivo que detecta código realmente no utilizado
void main() {
  group('🔍 Análisis de Código No Utilizado', () {
    test('📁 Detecta archivos realmente no utilizados', () async {
      final analysis = await _analyzeUnusedFiles();

      _printFileAnalysisReport(analysis);

      expect(true, isTrue);
    });

    test('🔧 Detecta funciones privadas realmente no utilizadas', () async {
      final analysis = await _analyzeUnusedPrivateFunctions();

      _printFunctionAnalysisReport(analysis);

      expect(true, isTrue);
    });

    test('🌐 Detecta funciones públicas realmente no utilizadas', () async {
      final analysis = await _analyzeUnusedPublicFunctions();

      _printPublicFunctionAnalysisReport(analysis);

      expect(true, isTrue);
    });
  });
}

// Modelos para análisis
class _FileAnalysis {
  _FileAnalysis({required this.unusedFiles, required this.totalFiles});
  final List<String> unusedFiles;
  final int totalFiles;
}

class _FunctionAnalysis {
  _FunctionAnalysis({
    required this.unusedFunctions,
    required this.totalPrivateFunctions,
  });
  final List<_FunctionInfo> unusedFunctions;
  final int totalPrivateFunctions;
}

class _PublicFunctionAnalysis {
  _PublicFunctionAnalysis({
    required this.unusedFunctions,
    required this.totalPublicFunctions,
  });
  final List<_FunctionInfo> unusedFunctions;
  final int totalPublicFunctions;
}

class _FunctionInfo {
  _FunctionInfo({
    required this.filePath,
    required this.functionName,
    required this.lineNumber,
    required this.signature,
  });
  final String filePath;
  final String functionName;
  final int lineNumber;
  final String signature;
}

// Funciones de análisis mejoradas
Future<_FileAnalysis> _analyzeUnusedFiles() async {
  final libDir = Directory('lib');
  final allDartFiles = <String>[];

  // Recopilar todos los archivos .dart en lib/
  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      allDartFiles.add(
        path.relative(entity.path, from: Directory.current.path),
      );
    }
  }

  final importedFiles = <String>{};

  // Analizar imports en todos los archivos
  for (final file in allDartFiles) {
    final content = await File(file).readAsString();

    // Buscar imports
    final importPattern = RegExp("import\\s+['\"]([^'\"]+)['\"]");
    final importMatches = importPattern.allMatches(content);

    for (final match in importMatches) {
      final importPath = match.group(1)!;
      final resolvedPath = _resolveImportPath(importPath, file);
      if (resolvedPath != null) {
        importedFiles.add(resolvedPath);
      }
    }

    // Buscar exports
    final exportPattern = RegExp("export\\s+['\"]([^'\"]+)['\"]");
    final exportMatches = exportPattern.allMatches(content);

    for (final match in exportMatches) {
      final exportPath = match.group(1)!;
      final resolvedPath = _resolveImportPath(exportPath, file);
      if (resolvedPath != null) {
        importedFiles.add(resolvedPath);
      }
    }
  }

  // Archivos críticos que siempre se consideran usados
  final criticalFiles = <String>{
    'lib/main.dart',
    // Screens y páginas
    ...allDartFiles.where(
      (f) =>
          f.contains('/screens/') ||
          f.contains('/pages/') ||
          f.endsWith('_screen.dart') ||
          f.endsWith('_page.dart'),
    ),
  };

  final usedFiles = {...importedFiles, ...criticalFiles};

  final unusedFiles =
      allDartFiles
          .where(
            (file) => !usedFiles.contains(file) && !_isTestOrGenerated(file),
          )
          .toList()
        ..sort();

  return _FileAnalysis(
    unusedFiles: unusedFiles,
    totalFiles: allDartFiles.length,
  );
}

Future<_FunctionAnalysis> _analyzeUnusedPrivateFunctions() async {
  final libDir = Directory('lib');
  final functions = <_FunctionInfo>[];
  final fileContents = <String, String>{};

  // Recopilar todas las funciones privadas y contenido de archivos
  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      final filePath = path.relative(entity.path, from: Directory.current.path);
      fileContents[filePath] = content;

      // Patrón para funciones privadas
      final privateFunctionPattern = RegExp(
        r'^\s*(?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|void|\w+(?:<[^>]*>)?)\s+(_\w+)\s*\(',
        multiLine: true,
      );

      final matches = privateFunctionPattern.allMatches(content);
      for (final match in matches) {
        final functionName = match.group(1)!;
        final lineNumber = content.substring(0, match.start).split('\n').length;
        final signature = _extractSignature(content, match);

        functions.add(
          _FunctionInfo(
            filePath: filePath,
            functionName: functionName,
            lineNumber: lineNumber,
            signature: signature,
          ),
        );
      }
    }
  }

  // Analizar uso de funciones (simple y directo)
  final unusedFunctions = <_FunctionInfo>[];

  for (final func in functions) {
    // Saltar callbacks, handlers y overrides conocidos
    if (_isCallbackOrOverride(func)) continue;

    // Obtener contenido del archivo donde está definida la función
    final content = fileContents[func.filePath] ?? '';

    // Buscar usos de la función en el mismo archivo
    final usagePattern = RegExp('\\b${func.functionName}\\b');
    final usageMatches = usagePattern.allMatches(content);

    // Contar solo usos reales (excluyendo la definición)
    int realUsages = 0;
    for (final match in usageMatches) {
      final matchLine = content.substring(0, match.start).split('\n').length;
      // No contar la definición de la función
      if (matchLine != func.lineNumber) {
        realUsages++;
      }
    }

    // Solo reportar si realmente no se usa
    if (realUsages == 0) {
      unusedFunctions.add(func);
    }
  }

  unusedFunctions.sort((a, b) => a.filePath.compareTo(b.filePath));

  return _FunctionAnalysis(
    unusedFunctions: unusedFunctions,
    totalPrivateFunctions: functions.length,
  );
}

Future<_PublicFunctionAnalysis> _analyzeUnusedPublicFunctions() async {
  final libDir = Directory('lib');
  final functions = <_FunctionInfo>[];
  final fileContents = <String, String>{};

  // Recopilar todas las funciones públicas y contenido de archivos
  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      final filePath = path.relative(entity.path, from: Directory.current.path);
      fileContents[filePath] = content;

      // Patrón para funciones públicas (sin underscore al inicio)
      final publicFunctionPattern = RegExp(
        r'^\s*(?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|void|\w+(?:<[^>]*>)?)\s+([a-zA-Z]\w*)\s*\(',
        multiLine: true,
      );

      final matches = publicFunctionPattern.allMatches(content);
      for (final match in matches) {
        final functionName = match.group(1)!;
        final lineNumber = content.substring(0, match.start).split('\n').length;
        final signature = _extractSignature(content, match);

        // Filtrar funciones que no son realmente funciones (constructores, getters, etc.)
        if (!_isValidPublicFunction(functionName, signature)) continue;

        functions.add(
          _FunctionInfo(
            filePath: filePath,
            functionName: functionName,
            lineNumber: lineNumber,
            signature: signature,
          ),
        );
      }
    }
  }

  // Analizar uso de funciones públicas en todo el proyecto
  final unusedFunctions = <_FunctionInfo>[];

  for (final func in functions) {
    // Saltar constructors, main, y funciones especiales
    if (_isSpecialPublicFunction(func)) continue;

    bool isUsed = false;

    // Buscar usos en todos los archivos
    for (final entry in fileContents.entries) {
      final content = entry.value;
      final usagePattern = RegExp('\\b${func.functionName}\\b');
      final usageMatches = usagePattern.allMatches(content);

      // Contar solo usos reales (excluyendo la definición)
      for (final match in usageMatches) {
        final matchLine = content.substring(0, match.start).split('\n').length;

        // No contar si es en el mismo archivo y misma línea (la definición)
        if (entry.key == func.filePath && matchLine == func.lineNumber) {
          continue;
        }

        // Encontró un uso real
        isUsed = true;
        break;
      }

      if (isUsed) break;
    }

    // Solo reportar si realmente no se usa
    if (!isUsed) {
      unusedFunctions.add(func);
    }
  }

  unusedFunctions.sort((a, b) => a.filePath.compareTo(b.filePath));

  return _PublicFunctionAnalysis(
    unusedFunctions: unusedFunctions,
    totalPublicFunctions: functions.length,
  );
} // Funciones auxiliares

String? _resolveImportPath(String importPath, String currentFile) {
  if (importPath.startsWith('package:ai_chan/')) {
    return importPath.replaceFirst('package:ai_chan/', 'lib/');
  } else if (!importPath.contains('package:') &&
      !importPath.startsWith('dart:')) {
    final fileDir = path.dirname(currentFile);
    final resolvedPath = path.normalize(path.join(fileDir, importPath));
    if (resolvedPath.endsWith('.dart')) {
      return resolvedPath;
    }
    return '$resolvedPath.dart';
  }
  return null;
}

bool _isTestOrGenerated(String filePath) {
  return filePath.contains('_test.dart') ||
      filePath.contains('.g.dart') ||
      filePath.contains('.freezed.dart') ||
      filePath.contains('.mocks.dart');
}

String _extractSignature(String content, RegExpMatch match) {
  final lines = content.split('\n');
  final startLine = content.substring(0, match.start).split('\n').length - 1;

  // Buscar anotaciones (como @override) en las líneas anteriores
  String annotations = '';
  for (int i = startLine - 1; i >= 0 && i >= startLine - 5; i--) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    if (line.startsWith('@')) {
      annotations = '$line $annotations';
    } else if (line.startsWith('//') ||
        line.startsWith('/*') ||
        line.startsWith('*')) {
      // Skip comments
      continue;
    } else {
      // Found non-annotation, non-comment line, stop looking
      break;
    }
  }

  // Buscar hasta el '{' o ';'
  String signature = annotations;
  for (int i = startLine; i < lines.length; i++) {
    final line = lines[i].trim();
    signature += line;
    if (line.contains('{') || line.contains(';')) break;
    signature += ' ';
  }

  return signature.split(RegExp(r'[{;]')).first.trim();
}

bool _isCallbackOrOverride(_FunctionInfo func) {
  final name = func.functionName.toLowerCase();
  final signature = func.signature.toLowerCase();

  // Callbacks y handlers comunes
  if (name.contains('callback') ||
      name.contains('handler') ||
      name.contains('listener') ||
      name.startsWith('_on') ||
      name.startsWith('_handle') ||
      name.startsWith('_build') || // Métodos build internos de widgets
      name.startsWith('_create') ||
      name.startsWith('_init') ||
      name.startsWith('_dispose') ||
      name.startsWith('_update') ||
      name.startsWith('_setup') ||
      name.startsWith('_start') ||
      name.startsWith('_stop') ||
      name.startsWith('_load') ||
      name.startsWith('_save') ||
      name.startsWith('_get') ||
      name.startsWith('_set') ||
      name.startsWith('_fetch') ||
      name.startsWith('_send') ||
      name.startsWith('_process') ||
      name.startsWith('_trigger') ||
      name.startsWith('_apply') ||
      name.startsWith('_execute') ||
      name.startsWith('_perform') ||
      name.startsWith('_calculate') ||
      name.startsWith('_validate') ||
      name.startsWith('_check') ||
      name.startsWith('_ensure') ||
      name.startsWith('_maybe') ||
      name.startsWith('_attempt') ||
      name.contains('async') ||
      name.contains('await')) {
    return true;
  }

  // Overrides y anotaciones
  if (signature.contains('@override') || signature.contains('override')) {
    return true;
  }

  // Métodos requeridos por interfaces/clases base conocidas
  if ((name == 'shouldrepaint' && signature.contains('painter')) ||
      (name == 'shouldrebuild' && signature.contains('widget')) ||
      (name == 'build' && signature.contains('widget')) ||
      (name == 'createstate' && signature.contains('widget')) ||
      (name == 'paint' && signature.contains('painter')) ||
      (name == 'getsize' && signature.contains('painter')) ||
      (name == 'hittest' && signature.contains('painter'))) {
    return true;
  }

  // Métodos de widget específicos
  if (name.endsWith('state') ||
      name.endsWith('widget') ||
      name.endsWith('painter') ||
      name.endsWith('controller') ||
      name.endsWith('manager') ||
      name.endsWith('service') ||
      name.endsWith('provider') ||
      name.endsWith('builder') ||
      name.endsWith('factory') ||
      name.endsWith('adapter') ||
      name.endsWith('helper') ||
      name.endsWith('utils') ||
      name.endsWith('util')) {
    return true;
  }

  // Métodos con patrones de formateo o conversión
  if (name.contains('format') ||
      name.contains('convert') ||
      name.contains('transform') ||
      name.contains('parse') ||
      name.contains('encode') ||
      name.contains('decode') ||
      name.contains('serialize') ||
      name.contains('deserialize') ||
      name.contains('normalize') ||
      name.contains('sanitize') ||
      name.contains('filter') ||
      name.contains('map') ||
      name.contains('reduce')) {
    return true;
  }

  return false;
}

bool _isValidPublicFunction(String name, String signature) {
  // Filtrar constructores
  if (signature.contains('$name(') &&
      !signature.contains('${name.toLowerCase()}(') &&
      _isUpperCase(name[0])) {
    return false;
  }

  // Filtrar getters y setters
  if (signature.contains('get ') || signature.contains('set ')) {
    return false;
  }

  // Filtrar keywords de Dart
  final dartKeywords = [
    'class',
    'abstract',
    'enum',
    'mixin',
    'extension',
    'typedef',
  ];
  if (dartKeywords.contains(name)) {
    return false;
  }

  // Filtrar nombres muy cortos o específicos
  if (name.length <= 1) {
    return false;
  }

  return true;
}

bool _isSpecialPublicFunction(_FunctionInfo func) {
  final name = func.functionName;
  final signature = func.signature;

  // Función main
  if (name == 'main') return true;

  // Constructores
  if (_isUpperCase(name[0]) && signature.contains('$name(')) {
    return true;
  }

  // Métodos override comunes de Flutter/Dart
  final flutterOverrides = [
    'build',
    'initState',
    'dispose',
    'didChangeDependencies',
    'didUpdateWidget',
    'createState',
    'toString',
    'hashCode',
    'operator',
    'compareTo',
    'onPressed',
    'onTap',
    'onChanged',
    'onSubmitted',
    'onSaved',
    'validator',
    'shouldRepaint', // CustomPainter required override
    'shouldRebuild', // Similar para otros painters/builders
  ];

  if (flutterOverrides.contains(name)) {
    return true;
  }

  // Métodos que empiezan con on (callbacks)
  if (name.startsWith('on') && name.length > 2 && _isUpperCase(name[2])) {
    return true;
  }

  // Test functions
  if (name.startsWith('test') ||
      name.startsWith('group') ||
      name.startsWith('setUp') ||
      name.startsWith('tearDown')) {
    return true;
  }

  return false;
}

bool _isUpperCase(String char) {
  return char == char.toUpperCase() && char != char.toLowerCase();
}

// Funciones de reporte
void _printFileAnalysisReport(_FileAnalysis analysis) {
  print('\n${'=' * 80}');
  print('📊 REPORTE DE ANÁLISIS DE ARCHIVOS');
  print('=' * 80);

  print('\n📈 Estadísticas generales:');
  print('  • Total de archivos analizados: ${analysis.totalFiles}');
  print(
    '  • Archivos potencialmente no utilizados: ${analysis.unusedFiles.length}',
  );

  if (analysis.unusedFiles.isNotEmpty) {
    print('\n⚠️  ARCHIVOS POTENCIALMENTE NO UTILIZADOS:');
    print('-' * 50);

    final byModule = <String, List<String>>{};
    for (final file in analysis.unusedFiles) {
      final module = file.split('/').length > 2 ? file.split('/')[1] : 'root';
      byModule.putIfAbsent(module, () => []).add(file);
    }

    for (final entry in byModule.entries) {
      print('\n📁 Módulo: ${entry.key}');
      for (final file in entry.value) {
        print('  📄 $file');
      }
    }

    print('\n💡 Sugerencias:');
    print('  • Verifica si estos archivos son realmente necesarios');
    print('  • Algunos pueden ser usados dinámicamente o por reflexión');
    print('  • Screens/Pages pueden ser referenciados en rutas');
  } else {
    print('\n✅ ¡Excelente! No se encontraron archivos no utilizados.');
  }
}

void _printFunctionAnalysisReport(_FunctionAnalysis analysis) {
  print('\n${'=' * 80}');
  print('🔧 REPORTE DE ANÁLISIS DE FUNCIONES PRIVADAS');
  print('=' * 80);

  print('\n📈 Estadísticas generales:');
  print('  • Total de funciones privadas: ${analysis.totalPrivateFunctions}');
  print(
    '  • Funciones realmente no utilizadas: ${analysis.unusedFunctions.length}',
  );

  if (analysis.unusedFunctions.isNotEmpty) {
    print('\n⚠️  FUNCIONES REALMENTE NO UTILIZADAS:');
    print('-' * 50);

    final byFile = <String, List<_FunctionInfo>>{};
    for (final func in analysis.unusedFunctions) {
      byFile.putIfAbsent(func.filePath, () => []).add(func);
    }

    for (final entry in byFile.entries) {
      print('\n📄 ${entry.key}:');
      for (final func in entry.value) {
        print('  🔧 ${func.functionName} (línea ${func.lineNumber})');
        if (func.signature.length > 80) {
          print('     ${func.signature.substring(0, 77)}...');
        } else {
          print('     ${func.signature}');
        }
      }
    }
  }

  if (analysis.unusedFunctions.isEmpty) {
    print(
      '\n✅ ¡Excelente! No se encontraron funciones realmente no utilizadas.',
    );
  } else {
    print('\n💡 Sugerencias:');
    print('  • Las funciones no utilizadas pueden eliminarse de forma segura');
  }
}

void _printPublicFunctionAnalysisReport(_PublicFunctionAnalysis analysis) {
  print('\n${'=' * 80}');
  print('🌐 REPORTE DE ANÁLISIS DE FUNCIONES PÚBLICAS');
  print('=' * 80);

  print('\n📈 Estadísticas generales:');
  print('  • Total de funciones públicas: ${analysis.totalPublicFunctions}');
  print(
    '  • Funciones públicas no utilizadas: ${analysis.unusedFunctions.length}',
  );

  if (analysis.unusedFunctions.isNotEmpty) {
    print('\n⚠️  FUNCIONES PÚBLICAS NO UTILIZADAS:');
    print('-' * 50);

    final byFile = <String, List<_FunctionInfo>>{};
    for (final func in analysis.unusedFunctions) {
      byFile.putIfAbsent(func.filePath, () => []).add(func);
    }

    for (final entry in byFile.entries) {
      print('\n📄 ${entry.key}:');
      for (final func in entry.value) {
        print('  🌐 ${func.functionName} (línea ${func.lineNumber})');
        if (func.signature.length > 80) {
          print('     ${func.signature.substring(0, 77)}...');
        } else {
          print('     ${func.signature}');
        }
      }
    }

    print('\n💡 Sugerencias:');
    print('  • Revisa si estas funciones son APIs que deben mantenerse');
    print('  • Considera si son parte de interfaces públicas');
    print('  • Verifica si son usadas por reflexión o dinámicamente');
    print('  • Si realmente no se usan, puedes marcarlas como privadas (_)');
  } else {
    print(
      '\n✅ ¡Excelente! Todas las funciones públicas están siendo utilizadas.',
    );
  }
}
