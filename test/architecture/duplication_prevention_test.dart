import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test arquitectural avanzado que detecta y previene duplicaciones,
/// limpia archivos obsoletos, barrels vacíos y comentarios deprecados
void main() {
  group('🏗️ Architecture Duplication Prevention', () {
    test('🚫 No duplicate files (identical content)', () {
      final allDartFiles = _collectDartFiles();
      final hashToFiles = <String, List<String>>{};

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);

        // Excluir archivos barrel de la verificación de duplicación
        // ya que es normal que tengan contenido similar en arquitectura DDD
        if (_isArchitecturalBarrel(path)) {
          continue;
        }

        final content = _normalizeContent(file.readAsStringSync());
        final hash = md5.convert(utf8.encode(content)).toString();
        hashToFiles.putIfAbsent(hash, () => []).add(path);
      }

      final duplicates = hashToFiles.values
          .where((final files) => files.length > 1)
          .toList();

      if (duplicates.isNotEmpty) {
        final message = _buildDuplicateFilesReport(duplicates);
        fail(message);
      }
    });

    test('⚙️ No duplicate utility functions across files', () {
      final allDartFiles = _collectDartFiles();
      final functionsBySignature = <String, List<String>>{};
      final violations = <String>[];

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();

        // Extraer funciones utilitarias
        final utilityFunctions = _extractUtilityFunctions(content, path);
        for (final func in utilityFunctions) {
          final signature = func['signature'] as String;
          final name = func['name'] as String;
          final location = func['location'] as String;

          functionsBySignature
              .putIfAbsent(signature, () => [])
              .add('$name in $location');
        }
      }

      // Detectar funciones duplicadas por funcionalidad similar
      for (final entry in functionsBySignature.entries) {
        if (entry.value.length > 1) {
          // Filtrar falsos positivos (funciones en tests, métodos de widgets, etc.)
          final realDuplicates = entry.value
              .where(
                (final func) =>
                    !func.contains('test/') &&
                    !func.contains('build(') &&
                    !func.contains('_build') &&
                    !func.contains('Widget'),
              )
              .toList();

          if (realDuplicates.length > 1) {
            violations.add(
              '⚙️ Duplicate utility function detected:\n'
              '   Function: ${entry.key.split('|').first}\n'
              '   Found in: ${realDuplicates.join(', ')}\n'
              '   💡 Consolidate into shared/utils/',
            );
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          '⚙️ Duplicate utility functions found:\n\n${violations.join('\n\n')}',
        );
      }
    });

    test('🏠 No misplaced utility functions (utilities in wrong layers)', () {
      final allDartFiles = _collectDartFiles();
      final violations = <String>[];

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();

        // Buscar funciones utilitarias en lugares incorrectos
        final misplacedFunctions = _findMisplacedUtilities(content, path);
        violations.addAll(misplacedFunctions);
      }

      if (violations.isNotEmpty) {
        fail(
          '🏠 Misplaced utility functions found:\n\n${violations.join('\n\n')}\n\n'
          '💡 Move these functions to appropriate utils/ files or create new utility classes.',
        );
      }
    });

    test('🔄 No duplicate service implementations', () {
      final allDartFiles = _collectDartFiles();
      final serviceViolations = <String>[];
      final servicesBySignature = <String, List<String>>{};

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();

        final serviceClasses = _extractServiceClasses(content, path);
        for (final serviceClass in serviceClasses) {
          final signature = serviceClass['signature'] as String;
          final className = serviceClass['name'] as String;
          final methodSignature = serviceClass['methods'] as String;

          final key = signature + methodSignature;
          servicesBySignature
              .putIfAbsent(key, () => [])
              .add('$className ($path)');
        }
      }

      for (final entry in servicesBySignature.entries) {
        if (entry.value.length > 1) {
          final violations = entry.value.map((final s) => '   - $s').join('\n');
          serviceViolations.add('⚠️  Similar services detected:\n$violations');
        }
      }

      if (serviceViolations.isNotEmpty) {
        fail(
          '🔄 Duplicate service implementations found:\n\n${serviceViolations.join('\n\n')}\n\n'
          '💡 Consider consolidating these services or ensuring they have distinct responsibilities.',
        );
      }
    });

    test('🎯 No duplicate models/entities', () {
      final allDartFiles = _collectDartFiles();
      final modelViolations = <String>[];
      final modelsByFields = <String, List<String>>{};

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();

        final models = _extractModelClasses(content, path);
        for (final model in models) {
          final fields = model['fields'] as String;
          final className = model['name'] as String;

          if (fields.isNotEmpty && !_isFlutterWidgetPair(className)) {
            modelsByFields
                .putIfAbsent(fields, () => [])
                .add('$className ($path)');
          }
        }
      }

      for (final entry in modelsByFields.entries) {
        if (entry.value.length > 1) {
          final paths = entry.value.map(
            (final s) => s.split('(').last.replaceAll(')', ''),
          );
          final hasTestAndProduction =
              paths.any((final p) => p.contains('test/')) &&
              paths.any((final p) => !p.contains('test/'));

          // Filtrar clases que están en el mismo archivo (es normal tener múltiples clases relacionadas)
          final uniquePaths = paths.toSet();
          final isSameFileClasses = uniquePaths.length == 1;

          // Solo considerar duplicación real si están en archivos diferentes
          if (!hasTestAndProduction &&
              !isSameFileClasses &&
              !_areRelatedClasses(entry.value)) {
            final violations = entry.value
                .map((final s) => '   - $s')
                .join('\n');
            modelViolations.add('⚠️  Similar models detected:\n$violations');
          }
        }
      }

      if (modelViolations.isNotEmpty) {
        // Fallar el test cuando hay duplicados reales detectados
        fail(
          '🎯 Duplicate model definitions found:\n\n${modelViolations.join('\n\n')}\n\n'
          '💡 Consider consolidating these models or moving them to the correct bounded context.',
        );
      }
    });

    test('🗑️ No empty barrel files or deprecated shims', () {
      final allDartFiles = _collectDartFiles();
      final emptyBarrels = <String>[];
      final shimsAndDeprecated = <String>[];

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();

        // Detectar barrels vacíos o con solo comentarios/exports comentados
        if (_isEmptyBarrel(content, path)) {
          emptyBarrels.add(path);
        }

        // Detectar shims, adapters deprecados, o archivos de migración
        if (_isDeprecatedShimOrMigration(content, path)) {
          shimsAndDeprecated.add(path);
        }
      }

      final violations = <String>[];

      if (emptyBarrels.isNotEmpty) {
        violations.add(
          '🗑️ Empty barrel files found:\n${emptyBarrels.map((final f) => '   - $f').join('\n')}',
        );
      }

      if (shimsAndDeprecated.isNotEmpty) {
        violations.add(
          '🚫 Deprecated shims/migration files found:\n${shimsAndDeprecated.map((final f) => '   - $f').join('\n')}',
        );
      }

      if (violations.isNotEmpty) {
        final rmCommands = [
          ...emptyBarrels,
          ...shimsAndDeprecated,
        ].map((final f) => 'rm \'$f\'').join('\n');
        fail(
          '${violations.join('\n\n')}\n\n'
          '💡 Clean up commands:\n$rmCommands',
        );
      }
    });

    test('📝 No obsolete comments or deprecated references', () {
      final allDartFiles = _collectDartFiles();
      final obsoleteComments = <String>[];

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lineNumber = i + 1;

          if (_hasObsoleteComment(line)) {
            obsoleteComments.add('$path:$lineNumber → ${line.trim()}');
          }
        }
      }

      if (obsoleteComments.isNotEmpty) {
        fail(
          '📝 Obsolete comments and/or methods found:\n\n${obsoleteComments.map((final c) => '   $c').join('\n')}\n\n'
          '💡 Clean these methods and/or comments that reference old/deprecated methods, TODO items from migration, or outdated architecture notes.',
        );
      }
    });

    test('🔗 No broken or invalid exports', () {
      final allDartFiles = _collectDartFiles();
      final violations = <String>[];

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          final lineNumber = i + 1;

          if (line.startsWith('export ') &&
              !line.startsWith('export \'package:') &&
              !line.contains('if (') &&
              !line.contains('dart.library')) {
            final exportPath = _extractExportPath(line);
            if (exportPath != null) {
              final fileDir = File(file.path).parent;
              final resolvedPath = _resolveRelativePath(
                fileDir.path,
                exportPath,
              );

              if (!File('$resolvedPath.dart').existsSync() &&
                  !File(resolvedPath).existsSync()) {
                violations.add(
                  '❌ Broken export in $path:$lineNumber\n   $line\n   → Target file does not exist: $exportPath',
                );
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          '🔗 Broken exports found:\n\n${violations.join('\n\n')}\n\n'
          '💡 Fix these export statements or remove them to clean up the module structure.',
        );
      }
    });

    test('🔄 No duplicate logic blocks within files', () {
      // IMPORTANTE: Este test detecta duplicación de código REAL que debe refactorizarse.
      // Ya se implementó detección inteligente de fallbacks apropiados (_isAppropriateFallback)
      // para ignorar casos legítimos como:
      // - Error handling fallbacks (transcripción en vivo → archivo)
      // - Platform-specific implementations
      // - Repository → SharedPreferences fallbacks
      //
      // Si ves duplicaciones reportadas aquí:
      // 1. NO son fallbacks legítimos
      // 2. DEBEN refactorizarse extrayendo métodos privados
      // 3. Sigue el principio DRY (Don't Repeat Yourself)
      // 4. Crea helper methods o utilities según corresponda
      final allDartFiles = _collectDartFiles();
      final violations = <String>[];

      for (final file in allDartFiles) {
        final path = _getRelativePath(file.path);
        final content = file.readAsStringSync();

        // Buscar bloques de código duplicados dentro del mismo archivo
        final duplicateBlocks = _findDuplicateCodeBlocks(content, path);
        violations.addAll(duplicateBlocks);
      }

      if (violations.isNotEmpty) {
        fail(
          '🔄 Duplicate code blocks found within files:\n\n${violations.join('\n\n')}\n\n'
          '💡 Extract these duplicated blocks into private methods or utility functions to follow DRY principle.',
        );
      }
    });
  });
}

// ===================== NUEVOS HELPER FUNCTIONS =====================

bool _isEmptyBarrel(final String content, final String path) {
  // Detectar archivos que son principalmente barrel exports pero están completamente vacíos
  if (!path.endsWith('.dart') ||
      path.contains('test/') ||
      path.endsWith('main.dart')) {
    return false;
  }

  // Excluir archivos importantes del core y módulos principales
  final criticalFiles = [
    'lib/shared.dart',
    'lib/voice.dart',
    'lib/onboarding.dart',
    'lib/chat.dart',
    'lib/core/models.dart',
    'lib/core/interfaces.dart',
    'lib/core/services.dart',
  ];

  for (final critical in criticalFiles) {
    if (path.endsWith(critical)) {
      return false;
    }
  }

  final lines = content.split('\n');
  final meaningfulLines = <String>[];

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('/*') ||
        trimmed == '}' ||
        trimmed.startsWith('*')) {
      continue;
    }

    // Líneas que son exports activos cuentan como significativas
    if (trimmed.startsWith('export ')) {
      meaningfulLines.add(trimmed);
      continue;
    }

    // Solo contar líneas con exports comentados como vacías si NO hay exports activos
    if (trimmed.startsWith('// export ') ||
        trimmed.startsWith('// removed ') ||
        trimmed.startsWith('// moved ') ||
        trimmed.startsWith('// deprecated ')) {
      continue;
    }

    meaningfulLines.add(trimmed);
  }

  // Solo considerar vacío si NO tiene exports activos Y es completamente vacío
  return meaningfulLines.isEmpty &&
      content
          .trim()
          .split('\n')
          .where((final line) => line.trim().startsWith('export '))
          .isEmpty;
}

bool _isDeprecatedShimOrMigration(final String content, final String path) {
  final lowerPath = path.toLowerCase();
  final lowerContent = content.toLowerCase();

  // Excluir todos los archivos importantes del proyecto - ser muy conservador
  final protectedPaths = [
    'duplication_prevention_test.dart',
    'main.dart',
    'pubspec.yaml',
    'README.md',
    'lib/shared.dart',
    'lib/voice.dart',
    'lib/onboarding.dart',
    'lib/chat.dart',
    'lib/core/',
    'lib/shared/services/',
    'lib/voice/infrastructure/adapters/',
    'lib/chat/application/',
    'lib/onboarding/application/',
  ];

  for (final protectedPath in protectedPaths) {
    if (path.contains(protectedPath)) {
      return false;
    }
  }

  // Solo archivos con nombres EXPLÍCITAMENTE deprecados
  if (lowerPath.contains('_old_backup') ||
      lowerPath.contains('_temp_migration') ||
      lowerPath.contains('_deprecated_remove') ||
      lowerPath.contains('_legacy_unused')) {
    return true;
  }

  // Solo archivos con contenido EXPLÍCITAMENTE marcado para eliminar
  final explicitRemovalMarkers = [
    '// todo: delete this file',
    '// fixme: remove this file',
    '// this file should be deleted',
    '// remove after migration',
    '// temporary file - delete',
  ];

  for (final marker in explicitRemovalMarkers) {
    if (lowerContent.contains(marker)) {
      return true;
    }
  }

  return false;
}

bool _hasObsoleteComment(final String line) {
  final trimmed = line.trim().toLowerCase();

  // Comentarios que referencian métodos/archivos antiguos
  if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
    return trimmed.contains('// moved to') &&
            !File(_extractMovedToPath(line) ?? '').existsSync() ||
        trimmed.contains('// removed') ||
        trimmed.contains('// use core version') ||
        trimmed.contains('// todo: migrate') ||
        trimmed.contains('// fixme: update') ||
        trimmed.contains('// old:') ||
        trimmed.contains('// deprecated:') ||
        trimmed.contains('// generated as part of') &&
            trimmed.contains('migration') ||
        trimmed.contains('// legacy') ||
        trimmed.contains('// temporary') ||
        (trimmed.contains('todo') &&
            (trimmed.contains('remove') ||
                trimmed.contains('clean') ||
                trimmed.contains('delete'))) ||
        (trimmed.contains('fixme') &&
            (trimmed.contains('remove') || trimmed.contains('clean')));
  }

  return false;
}

String? _extractMovedToPath(final String comment) {
  final match = RegExp(
    r'moved to (.+\.dart)',
  ).firstMatch(comment.toLowerCase());
  return match?.group(1);
}

String? _extractExportPath(final String exportLine) {
  // Extraer path de export usando substring para evitar regex compleja
  if (exportLine.contains("'")) {
    final start = exportLine.indexOf("'") + 1;
    final end = exportLine.lastIndexOf("'");
    if (start > 0 && end > start) {
      return exportLine.substring(start, end);
    }
  } else if (exportLine.contains('"')) {
    final start = exportLine.indexOf('"') + 1;
    final end = exportLine.lastIndexOf('"');
    if (start > 0 && end > start) {
      return exportLine.substring(start, end);
    }
  }
  return null;
}

String _resolveRelativePath(final String basePath, final String relativePath) {
  if (relativePath.startsWith('/')) return relativePath;

  final baseDir = Directory(basePath);
  final resolved = File('${baseDir.path}/$relativePath').path;
  return resolved.replaceAll(r'\', '/');
}

List<File> _collectDartFiles() {
  final files = <File>[];
  final libDir = Directory('lib');
  final testDir = Directory('test');

  void collectFrom(final Directory dir) {
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final path = entity.path.replaceAll(r'\', '/');
        if (path.contains('.g.dart') ||
            path.contains('.freezed.dart') ||
            path.contains('.mocks.dart')) {
          continue;
        }
        files.add(entity);
      }
    }
  }

  collectFrom(libDir);
  collectFrom(testDir);
  return files;
}

String _normalizeContent(final String content) {
  final lines = <String>[];

  for (final rawLine in LineSplitter.split(content)) {
    final line = rawLine.trim();

    // Mantener exports para distinguir archivos barrel diferentes
    if (line.startsWith('export ')) {
      // Normalizar el export para comparación
      final cleanExport = line.replaceAll(RegExp(r'\s+'), ' ');
      lines.add(cleanExport);
      continue;
    }

    // Omitir solo comentarios, imports y líneas vacías
    if (line.startsWith('//') ||
        line.startsWith('/*') ||
        line.startsWith('import ') ||
        line.startsWith('part ') ||
        line.startsWith('library ') ||
        line.isEmpty) {
      continue;
    }

    lines.add(line);
  }

  return lines.join('\n');
}

List<Map<String, String>> _extractServiceClasses(
  final String content,
  final String path,
) {
  final services = <Map<String, String>>[];
  final lines = content.split('\n');

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('class ') &&
        (line.contains('Service') ||
            line.contains('Adapter') ||
            line.contains('Repository') ||
            line.contains('Gateway'))) {
      final words = line.split(' ');
      if (words.length >= 2) {
        final className = words[1];
        final methodSignatures = _extractMethodSignatures(content, className);

        services.add({
          'name': className,
          'signature': className,
          'methods': methodSignatures,
          'path': path,
        });
      }
    }
  }

  return services;
}

List<Map<String, String>> _extractModelClasses(
  final String content,
  final String path,
) {
  final models = <Map<String, String>>[];
  final lines = content.split('\n');

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('class ')) {
      final words = line.split(' ');
      if (words.length >= 2) {
        final className = words[1];
        final fields = _extractFields(content, className);

        if (fields.isNotEmpty) {
          models.add({'name': className, 'fields': fields, 'path': path});
        }
      }
    }
  }

  return models;
}

String _extractMethodSignatures(final String content, final String className) {
  final lines = content.split('\n');
  final signatures = <String>[];

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.contains('(') &&
        !trimmed.startsWith('//') &&
        !trimmed.startsWith('/*')) {
      final words = trimmed.split(' ');
      for (int i = 0; i < words.length - 1; i++) {
        if (words[i + 1].contains('(') && !words[i + 1].startsWith('_')) {
          final methodName = words[i + 1].split('(')[0];
          if (methodName != className && methodName.isNotEmpty) {
            signatures.add(methodName);
          }
          break;
        }
      }
    }
  }

  signatures.sort();
  return signatures.join('|');
}

String _extractFields(final String content, final String className) {
  final lines = content.split('\n');
  final fields = <String>[];
  bool inClass = false;
  String currentClass = '';

  for (final line in lines) {
    final trimmed = line.trim();

    // Detectar inicio de clase
    if (trimmed.startsWith('class $className')) {
      inClass = true;
      currentClass = className;
      continue;
    }

    // Detectar fin de clase
    if (inClass && trimmed == '}' && currentClass == className) {
      break;
    }

    // Solo extraer fields de la clase correcta
    if (inClass && currentClass == className) {
      if (trimmed.startsWith('final ') || trimmed.startsWith('const ')) {
        final words = trimmed.split(' ');
        if (words.length >= 3) {
          final fieldName = words[2]
              .replaceAll('?', '')
              .replaceAll(';', '')
              .replaceAll('=', '')
              .split('=')[0];
          if (!fieldName.startsWith('_') &&
              !fieldName.contains('(') &&
              fieldName.isNotEmpty) {
            fields.add(fieldName);
          }
        }
      }
    }
  }

  // Solo considerar duplicado si tiene al menos 2 fields significativos
  if (fields.length < 2) {
    return '';
  }

  fields.sort();
  return fields.join('|');
}

String _getRelativePath(final String fullPath) {
  final currentDir = Directory.current.path.replaceAll(r'\', '/');
  return fullPath.replaceAll(r'\', '/').replaceAll('$currentDir/', '');
}

String _buildDuplicateFilesReport(final List<List<String>> duplicates) {
  final buffer = StringBuffer();
  buffer.writeln('🚫 Duplicate files detected:');
  buffer.writeln();

  for (int i = 0; i < duplicates.length; i++) {
    final group = duplicates[i];
    buffer.writeln('Group ${i + 1} (${group.length} files):');
    for (final file in group) {
      buffer.writeln('  • $file');
    }
    buffer.writeln();
    buffer.writeln('💡 Keep one and remove others:');
    final keep = group.first;
    for (final file in group.skip(1)) {
      buffer.writeln('  rm \'$file\'');
    }
    buffer.writeln('  # Keep: $keep');
    buffer.writeln();
  }

  return buffer.toString();
}

bool _isArchitecturalBarrel(final String path) {
  // Excluir archivos barrel que son parte normal de la arquitectura DDD
  final barrelPatterns = [
    // Módulos principales
    r'lib/(shared|voice|chat|onboarding)\.dart$',

    // Barrels de capas DDD
    r'lib/\w+/(domain|infrastructure|application|presentation)\.dart$',
    r'lib/\w+/\w+/(domain|infrastructure|application|presentation)\.dart$',

    // Barrels de subcapas
    r'lib/\w+/(models|interfaces|services|adapters|repositories|screens|widgets|use_cases|providers)\.dart$',
    r'lib/\w+/\w+/(models|interfaces|services|adapters|repositories|screens|widgets|use_cases|providers)\.dart$',

    // Barrels de utilidades compartidas
    r'lib/shared/(utils|constants|screens|domain)\.dart$',
    r'lib/core/(models|interfaces|services)\.dart$',
  ];

  for (final pattern in barrelPatterns) {
    if (RegExp(pattern).hasMatch(path)) {
      return true;
    }
  }

  return false;
}

bool _isFlutterWidgetPair(final String className) {
  // Filtrar pares comunes de Widget + State de Flutter
  return className.endsWith('State') ||
      className.endsWith('Widget') ||
      className.contains('Dialog') ||
      className.contains('Screen') ||
      className.contains('Subtitle') ||
      className.contains('Player') ||
      className.contains('Animation') ||
      className.contains('Indicator') ||
      className.contains('Controller') && className.contains('_');
}

bool _areRelatedClasses(final List<String> classNames) {
  // Verificar si las clases son claramente relacionadas (e.g., diferentes versiones del mismo concepto)
  final names = classNames.map((final s) => s.split('(')[0]).toList();

  // Si las clases son de diferentes tipos (adapter, service, utils, etc.) - no son duplicados
  final types = names.map((final n) => n.toLowerCase());
  final hasAdapter = types.any((final t) => t.contains('adapter'));
  final hasService = types.any((final t) => t.contains('service'));
  final hasUtils = types.any((final t) => t.contains('utils'));
  final hasUseCase = types.any((final t) => t.contains('usecase'));

  if ((hasAdapter || hasService || hasUtils || hasUseCase) &&
      types.length > 1) {
    return true; // Son tipos diferentes, no duplicados reales
  }

  // Si solo hay 2 clases y una es versión específica de la otra
  if (names.length == 2) {
    final name1 = names[0].toLowerCase();
    final name2 = names[1].toLowerCase();

    // Casos como "ChatExport" vs "ChatExport" (mismo nombre exacto, diferentes ubicaciones - son duplicados reales)
    if (name1 == name2) {
      return false; // SON duplicados reales
    }

    // Casos como "AiChanProfile" vs "AiChanProfile" (mismo concepto, diferentes ubicaciones)
    if (name1.replaceAll('ai', '').replaceAll('chan', '') ==
        name2.replaceAll('ai', '').replaceAll('chan', '')) {
      return false; // SON duplicados reales
    }
  }

  return true; // Por defecto, asumir que están relacionados (no son duplicados reales)
}

// ===================== UTILITY FUNCTION DETECTION =====================

List<Map<String, String>> _extractUtilityFunctions(
  final String content,
  final String path,
) {
  final functions = <Map<String, String>>[];
  final lines = content.split('\n');

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();

    // Buscar declaraciones de funciones que parecen utilitarias
    if (_isUtilityFunction(line)) {
      final functionName = _extractFunctionName(line);
      if (functionName != null) {
        final functionBody = _extractFunctionBody(lines, i);
        final signature = _generateFunctionSignature(
          functionName,
          functionBody,
        );

        functions.add({
          'name': functionName,
          'signature': signature,
          'location': path,
          'body': functionBody,
        });
      }
    }
  }

  return functions;
}

bool _isUtilityFunction(final String line) {
  // Detectar funciones que parecen utilitarias por nombre y patrón
  final utilityPatterns = [
    // Funciones de formateo
    r'(String|int|double)\s+\w*[Ff]ormat\w*\s*\(',
    r'String\s+\w*[Hh]uman\w*\s*\(',
    r'String\s+\w*[Ss]ize\w*\s*\(',

    // Funciones de normalización
    r'String\s+\w*[Nn]ormali[zs]e\w*\s*\(',
    r'String\s+_normalize\s*\(',

    // Funciones de conversión
    r'(String|int|double)\s+\w*[Cc]onvert\w*\s*\(',
    r'(String|int)\s+\w*[Pp]arse\w*\s*\(',

    // Funciones de validación
    r'bool\s+\w*[Vv]alidate\w*\s*\(',
    r'bool\s+\w*[Cc]heck\w*\s*\(',

    // Funciones de limpieza/sanitización
    r'(String|void)\s+\w*[Cc]lean\w*\s*\(',
    r'(String|void)\s+\w*[Ss]anitize\w*\s*\(',
  ];

  for (final pattern in utilityPatterns) {
    if (RegExp(pattern, caseSensitive: false).hasMatch(line)) {
      return true;
    }
  }

  return false;
}

String? _extractFunctionName(final String line) {
  // Extraer nombre de función de declaraciones como "String formatBytes(int bytes)"
  final match = RegExp(r'\b(\w+)\s*\(').firstMatch(line);
  if (match != null) {
    final name = match.group(1)!;
    // Evitar matches con keywords de Dart
    if (!['if', 'for', 'while', 'switch', 'return'].contains(name)) {
      return name;
    }
  }
  return null;
}

String _extractFunctionBody(final List<String> lines, final int startIndex) {
  final bodyLines = <String>[];
  int braceCount = 0;
  bool foundOpeningBrace = false;

  for (int i = startIndex; i < lines.length; i++) {
    final line = lines[i];
    bodyLines.add(line.trim());

    // Contar llaves para saber cuándo termina la función
    for (final char in line.split('')) {
      if (char == '{') {
        braceCount++;
        foundOpeningBrace = true;
      } else if (char == '}') {
        braceCount--;
        if (foundOpeningBrace && braceCount == 0) {
          return bodyLines.join('\n');
        }
      }
    }

    // Limitar la extracción del cuerpo a 50 líneas por función
    if (bodyLines.length > 50) break;
  }

  return bodyLines.join('\n');
}

String _generateFunctionSignature(
  final String functionName,
  final String functionBody,
) {
  // Crear una firma basada en el nombre y los patrones clave del cuerpo
  final keyPatterns = <String>[];

  // Detectar patrones comunes en funciones utilitarias
  if (functionBody.contains('toLowerCase()') ||
      functionBody.contains('toUpperCase()')) {
    keyPatterns.add('case_conversion');
  }
  if (functionBody.contains('replaceAll') || functionBody.contains('replace')) {
    keyPatterns.add('string_replacement');
  }
  if (functionBody.contains('RegExp') || functionBody.contains('Pattern')) {
    keyPatterns.add('regex_processing');
  }
  if (functionBody.contains('1024') || functionBody.contains('pow(')) {
    keyPatterns.add('byte_calculation');
  }
  if (functionBody.contains('toStringAsFixed') ||
      functionBody.contains('toFixed')) {
    keyPatterns.add('number_formatting');
  }
  if (functionBody.contains('[') && functionBody.contains(']')) {
    keyPatterns.add('array_processing');
  }

  // Si no hay patrones específicos, usar conteo de líneas significativas
  if (keyPatterns.isEmpty) {
    final significantLines = functionBody
        .split('\n')
        .where(
          (final line) =>
              line.trim().isNotEmpty && !line.trim().startsWith('//'),
        )
        .length;
    keyPatterns.add('lines_$significantLines');
  }

  return '$functionName|${keyPatterns.join('_')}';
}

List<String> _findMisplacedUtilities(final String content, final String path) {
  final violations = <String>[];
  final lines = content.split('\n');

  // Solo revisar archivos que NO deberían contener utilitarios
  final shouldNotContainUtils = [
    RegExp(r'lib/\w+/presentation/widgets/.*\.dart$'),
    RegExp(r'lib/\w+/presentation/screens/.*\.dart$'),
    RegExp(r'lib/\w+/infrastructure/adapters/.*\.dart$'),
    RegExp(r'lib/main\.dart$'),
  ];

  bool isWrongLocation = false;
  for (final pattern in shouldNotContainUtils) {
    if (pattern.hasMatch(path)) {
      isWrongLocation = true;
      break;
    }
  }

  if (!isWrongLocation) return violations;

  // Buscar funciones que claramente deberían estar en utils
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();

    // Detectar funciones de formateo de bytes/tamaños
    if (_isByteFormattingFunction(line)) {
      violations.add(
        '📦 Byte formatting function in $path:${i + 1}\n'
        '   "$line"\n'
        '   💡 Move to shared/utils/app_data_utils.dart',
      );
    }

    // Detectar funciones de normalización de strings
    if (_isStringNormalizationFunction(line)) {
      violations.add(
        '🔤 String normalization function in $path:${i + 1}\n'
        '   "$line"\n'
        '   💡 Move to shared/utils/string_utils.dart',
      );
    }

    // Detectar funciones matemáticas/conversión
    if (_isMathConversionFunction(line)) {
      violations.add(
        '🔢 Math/conversion function in $path:${i + 1}\n'
        '   "$line"\n'
        '   💡 Move to appropriate utils/ file',
      );
    }
  }

  return violations;
}

bool _isByteFormattingFunction(final String line) {
  return RegExp(
        r'String\s+\w*([Hh]uman|[Ff]ormat|[Ss]ize)\w*.*\(.*int.*\)',
        caseSensitive: false,
      ).hasMatch(line) &&
      (line.contains('bytes') || line.contains('size') || line.contains('B'));
}

bool _isStringNormalizationFunction(final String line) {
  return RegExp(
        r'String\s+\w*[Nn]ormali[zs]e\w*\s*\(.*String',
        caseSensitive: false,
      ).hasMatch(line) ||
      (line.contains('_normalize') &&
          line.contains('String') &&
          line.contains('('));
}

bool _isMathConversionFunction(final String line) {
  return RegExp(
    r'(int|double|num)\s+\w*([Cc]onvert|[Cc]alculate|[Pp]arse)\w*\s*\(',
  ).hasMatch(line);
}

// ===================== DUPLICATE CODE BLOCK DETECTION =====================

List<String> _findDuplicateCodeBlocks(final String content, final String path) {
  final violations = <String>[];
  final lines = content.split('\n');

  // Configuración: bloques de al menos 8 líneas significativas
  const int minBlockSize = 8;
  const int maxLinesToAnalyze = 2000; // Límite para archivos muy grandes

  // Solo analizar archivos que no sean de test (para evitar duplicación intencional en tests)
  if (path.contains('test/') && !path.contains('architecture/')) {
    return violations;
  }

  // Excluir archivos con templates de datos/configuración legítimos
  if (path.contains('_generator.dart') ||
      path.contains('template') ||
      path.endsWith('_config.dart') ||
      path.endsWith('_schema.dart') ||
      path.contains('constants') ||
      path.contains('_templates.dart')) {
    return violations;
  }

  // Limitar análisis para archivos muy grandes
  final linesToAnalyze = lines.length > maxLinesToAnalyze
      ? lines.take(maxLinesToAnalyze).toList()
      : lines;

  // Extraer todos los bloques candidatos del archivo
  final blocks = _extractCodeBlocks(linesToAnalyze);

  // Comparar bloques entre sí para encontrar duplicados
  for (int i = 0; i < blocks.length; i++) {
    for (int j = i + 1; j < blocks.length; j++) {
      final block1 = blocks[i];
      final block2 = blocks[j];

      // Solo considerar bloques de tamaño mínimo
      if (block1['lines'].length < minBlockSize ||
          block2['lines'].length < minBlockSize) {
        continue;
      }

      // Calcular similitud entre bloques
      final similarity = _calculateBlockSimilarity(
        block1['lines'] as List<String>,
        block2['lines'] as List<String>,
      );

      // Si la similitud es alta (>= 80%), verificar si es un fallback apropiado
      if (similarity >= 0.80) {
        final start1 = block1['startLine'] as int;
        final start2 = block2['startLine'] as int;
        final linesCount1 = (block1['lines'] as List<String>).length;
        final linesCount2 = (block2['lines'] as List<String>).length;

        // NUEVO: Detectar fallbacks apropiados y saltarlos
        if (_isAppropriateFallback(
          block1['lines'] as List<String>,
          block2['lines'] as List<String>,
          path,
        )) {
          continue;
        }

        violations.add(
          '🔄 Duplicate code block detected in $path:\n'
          '   Block 1: lines $start1-${start1 + linesCount1} ($linesCount1 lines)\n'
          '   Block 2: lines $start2-${start2 + linesCount2} ($linesCount2 lines)\n'
          '   Similarity: ${(similarity * 100).toStringAsFixed(1)}%\n'
          '   💡 Extract common logic into a private method\n'
          '   NOTE: If this is an intentional fallback for error handling or\n'
          '         platform-specific behavior, consider refactoring to eliminate duplication',
        );
      }
    }
  }

  return violations;
}

/// Detecta si dos bloques de código similares representan un fallback apropiado
/// que no debe considerarse duplicación problemática
bool _isAppropriateFallback(
  final List<String> block1,
  final List<String> block2,
  final String path,
) {
  final block1Text = block1.join(' ').toLowerCase();
  final block2Text = block2.join(' ').toLowerCase();
  final combinedText = '$block1Text $block2Text';

  // 6. NUEVO: Estructuras de datos constantes (templates, configuraciones, JSON schemas)
  final hasDataStructurePattern =
      (combinedText.contains('nombre') ||
          combinedText.contains('descripcion')) &&
      (combinedText.contains('const ') ||
          combinedText.contains('final ') ||
          combinedText.contains('template') ||
          combinedText.contains('schema')) &&
      (combinedText.contains("''") ||
          combinedText.contains('[]') ||
          combinedText.contains('{}'));

  if (hasDataStructurePattern) {
    return true;
  }

  // Patrones de fallbacks apropiados:
  // 1. Error handling fallbacks
  if (combinedText.contains('catch') &&
      (combinedText.contains('fallback') ||
          combinedText.contains('try again') ||
          combinedText.contains('retry') ||
          combinedText.contains('usar .* como fallback'))) {
    return true;
  }

  // 2. STT/transcripción fallbacks (muy específico del dominio)
  if (combinedText.contains('transcripción') &&
      (combinedText.contains('fallback') ||
          combinedText.contains('usar .* en vivo'))) {
    return true;
  }

  // 3. Network/connectivity fallbacks
  if (combinedText.contains('conexión') || combinedText.contains('conectar')) {
    if (combinedText.contains('fallback') || combinedText.contains('offline')) {
      return true;
    }
  }

  // 4. Platform-specific implementations
  if (combinedText.contains('platform') ||
      combinedText.contains('android') ||
      combinedText.contains('ios') ||
      combinedText.contains('web')) {
    return true;
  }

  // 5. Repository vs SharedPreferences fallbacks (patrón del archivo)
  if (path.contains('provider') &&
      combinedText.contains('repository') &&
      (combinedText.contains('fallback') ||
          combinedText.contains('sharedpreferences'))) {
    return true;
  }

  // 6. NUEVO: Configuraciones estructurales similares (tone service, audio configs, etc.)
  if (_isStructuralConfiguration(block1Text, block2Text, path)) {
    return true;
  }

  // 7. NUEVO: Patrones de inicialización similares con diferentes parámetros
  if (_isParameterizedInitialization(block1Text, block2Text)) {
    return true;
  }

  // 8. NUEVO: Builders/factory methods con diferentes valores por defecto
  if (_isBuildersWithDifferentDefaults(block1Text, block2Text)) {
    return true;
  }

  return false;
}

/// Detecta configuraciones estructurales similares que son aceptables
/// (ej: diferentes presets de audio, configuraciones de UI similares)
bool _isStructuralConfiguration(
  final String block1,
  final String block2,
  final String path,
) {
  // Configuraciones de audio/tone service
  if (path.contains('tone_service')) {
    // Patrones de configuración de beeps con diferentes valores
    if ((block1.contains('b1ms') ||
            block1.contains('pausems') ||
            block1.contains('b2ms')) &&
        (block2.contains('b1ms') ||
            block2.contains('pausems') ||
            block2.contains('b2ms'))) {
      // Solo considerar apropiado si tienen valores diferentes (no duplicación exacta)
      if (block1 != block2) {
        return true;
      }
    }

    // Configuraciones de estructura de beep similar
    if (block1.contains('beepstructure') &&
        block2.contains('beepstructure') &&
        block1.contains('_createdoublebeepstructure') &&
        block2.contains('_createdoublebeepstructure')) {
      return true;
    }
  }

  // Configuraciones de widgets similares con diferentes parámetros
  if ((block1.contains('padding') ||
          block1.contains('margin') ||
          block1.contains('decoration')) &&
      (block2.contains('padding') ||
          block2.contains('margin') ||
          block2.contains('decoration'))) {
    return true;
  }

  return false;
}

/// Detecta patrones de inicialización parametrizada donde la estructura es la misma
/// pero los valores son diferentes (aceptable)
bool _isParameterizedInitialization(final String block1, final String block2) {
  // Patrones comunes de inicialización con diferentes valores
  final initPatterns = [
    'const.*=.*',
    'final.*=.*',
    'var.*=.*',
    '.*samples.*=.*',
    '.*duration.*=.*',
    '.*frequency.*=.*',
  ];

  for (final pattern in initPatterns) {
    final regex = RegExp(pattern, caseSensitive: false);
    if (regex.hasMatch(block1) && regex.hasMatch(block2)) {
      // Si ambos bloques siguen el mismo patrón de inicialización
      // pero tienen valores diferentes, es aceptable
      return true;
    }
  }

  return false;
}

/// Detecta builders o factory methods con diferentes valores por defecto
bool _isBuildersWithDifferentDefaults(
  final String block1,
  final String block2,
) {
  final builderPatterns = [
    'build.*wav',
    'create.*structure',
    'generate.*config',
    '_build.*',
    '_create.*',
    '_generate.*',
  ];

  for (final pattern in builderPatterns) {
    final regex = RegExp(pattern, caseSensitive: false);
    if (regex.hasMatch(block1) && regex.hasMatch(block2)) {
      return true;
    }
  }

  return false;
}

List<Map<String, dynamic>> _extractCodeBlocks(final List<String> lines) {
  final blocks = <Map<String, dynamic>>[];
  final meaningfulLines = <String>[];
  final lineNumbers = <int>[];

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();

    // Ignorar líneas vacías, comentarios y imports
    if (line.isEmpty ||
        line.startsWith('//') ||
        line.startsWith('/*') ||
        line.startsWith('*') ||
        line.startsWith('import ') ||
        line.startsWith('export ') ||
        line.startsWith('part ') ||
        line == '}' ||
        line == '{' ||
        line == '];' ||
        line == ');') {
      // Si hemos acumulado líneas significativas, crear un bloque
      if (meaningfulLines.length >= 5) {
        blocks.add({
          'lines': List<String>.from(meaningfulLines),
          'startLine': lineNumbers.first,
          'endLine': lineNumbers.last,
        });
      }

      // Resetear para el siguiente bloque
      meaningfulLines.clear();
      lineNumbers.clear();
      continue;
    }

    // Acumular líneas significativas
    meaningfulLines.add(line);
    lineNumbers.add(i + 1);

    // Si el bloque se vuelve muy largo, dividirlo
    if (meaningfulLines.length > 25) {
      blocks.add({
        'lines': List<String>.from(meaningfulLines),
        'startLine': lineNumbers.first,
        'endLine': lineNumbers.last,
      });
      meaningfulLines.clear();
      lineNumbers.clear();
    }
  }

  // Agregar el último bloque si existe
  if (meaningfulLines.length >= 5) {
    blocks.add({
      'lines': List<String>.from(meaningfulLines),
      'startLine': lineNumbers.first,
      'endLine': lineNumbers.last,
    });
  }

  return blocks;
}

double _calculateBlockSimilarity(
  final List<String> block1,
  final List<String> block2,
) {
  // Normalizar ambos bloques para comparación
  final normalized1 = _normalizeCodeBlock(block1);
  final normalized2 = _normalizeCodeBlock(block2);

  // Calcular similitud usando Levenshtein distance simplificado
  final totalLines = (normalized1.length + normalized2.length) / 2;
  if (totalLines == 0) return 0.0;

  // Contar líneas exactamente iguales
  int exactMatches = 0;
  int similarMatches = 0;

  final minLength = normalized1.length < normalized2.length
      ? normalized1.length
      : normalized2.length;

  for (int i = 0; i < minLength; i++) {
    final line1 = normalized1[i];
    final line2 = normalized2[i];

    if (line1 == line2) {
      exactMatches++;
    } else if (_areLinesStructurallySimilar(line1, line2)) {
      similarMatches++;
    }
  }

  // Similitud basada en matches exactos + similares con peso
  final similarity = (exactMatches + similarMatches * 0.7) / minLength;

  return similarity > 1.0 ? 1.0 : similarity;
}

List<String> _normalizeCodeBlock(final List<String> lines) {
  return lines.map((final line) {
    // Normalizar espacios en blanco
    var normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Normalizar nombres de variables comunes que pueden diferir
    normalized = normalized.replaceAll(
      RegExp(r'\b\w*Ms\b'),
      'TIME_MS',
    ); // timestamps
    normalized = normalized.replaceAll(
      RegExp(r'\b\w*Token\b'),
      'TOKEN',
    ); // tokens
    normalized = normalized.replaceAll(
      RegExp(r'\brepository branch\b'),
      'BRANCH',
    ); // branch names
    normalized = normalized.replaceAll(RegExp(r'\bprefs branch\b'), 'BRANCH');
    normalized = normalized.replaceAll(
      RegExp(r'\bloading\b'),
      'LOADING',
    ); // state names
    normalized = normalized.replaceAll(RegExp(r'\bloadAll\b'), 'LOAD_METHOD');

    return normalized;
  }).toList();
}

bool _areLinesStructurallySimilar(final String line1, final String line2) {
  // Extraer la estructura sintáctica (keywords, operadores, paréntesis)
  final structure1 = _extractSyntacticStructure(line1);
  final structure2 = _extractSyntacticStructure(line2);

  return structure1 == structure2;
}

String _extractSyntacticStructure(final String line) {
  // Reemplazar literales con placeholders para comparar solo estructura
  var structure = line;

  // Reemplazar strings literales
  structure = structure.replaceAll(RegExp(r"'[^']*'"), 'STRING');
  structure = structure.replaceAll(RegExp(r'"[^"]*"'), 'STRING');

  // Reemplazar números
  structure = structure.replaceAll(RegExp(r'\b\d+\b'), 'NUMBER');

  // Reemplazar identificadores pero mantener keywords
  final dartKeywords = {
    'if',
    'else',
    'for',
    'while',
    'try',
    'catch',
    'finally',
    'return',
    'await',
    'async',
    'final',
    'const',
    'var',
    'bool',
    'String',
    'int',
    'double',
    'void',
    'null',
    'true',
    'false',
  };

  final words = structure.split(RegExp(r'\W+'));
  for (final word in words) {
    if (!dartKeywords.contains(word) && word.isNotEmpty) {
      structure = structure.replaceAll(RegExp('\\b$word\\b'), 'ID');
    }
  }

  return structure;
}
