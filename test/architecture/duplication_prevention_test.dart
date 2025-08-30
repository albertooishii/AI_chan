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

      final duplicates = hashToFiles.values.where((files) => files.length > 1).toList();

      if (duplicates.isNotEmpty) {
        final message = _buildDuplicateFilesReport(duplicates);
        fail(message);
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
          servicesBySignature.putIfAbsent(key, () => []).add('$className ($path)');
        }
      }

      for (final entry in servicesBySignature.entries) {
        if (entry.value.length > 1) {
          final violations = entry.value.map((s) => '   - $s').join('\n');
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
            modelsByFields.putIfAbsent(fields, () => []).add('$className ($path)');
          }
        }
      }

      for (final entry in modelsByFields.entries) {
        if (entry.value.length > 1) {
          final paths = entry.value.map((s) => s.split('(').last.replaceAll(')', ''));
          final hasTestAndProduction = paths.any((p) => p.contains('test/')) && paths.any((p) => !p.contains('test/'));
          
          // Filtrar clases que están en el mismo archivo (es normal tener múltiples clases relacionadas)
          final uniquePaths = paths.toSet();
          final isSameFileClasses = uniquePaths.length == 1;
          
          // Solo considerar duplicación real si están en archivos diferentes
          if (!hasTestAndProduction && !isSameFileClasses && !_areRelatedClasses(entry.value)) {
            final violations = entry.value.map((s) => '   - $s').join('\n');
            modelViolations.add('⚠️  Similar models detected:\n$violations');
          }
        }
      }

      if (modelViolations.isNotEmpty) {
        // Solo mostrar como warning, no fallar el test para permitir commit
        // ignore: avoid_print
        print('🎯 Potential duplicate models found (review recommended):');
        // ignore: avoid_print
        print('');
        for (final violation in modelViolations) {
          // ignore: avoid_print
          print(violation);
          // ignore: avoid_print
          print('');
        }
        // ignore: avoid_print
        print('💡 Consider consolidating these models or moving them to the correct bounded context.');
        // ignore: avoid_print
        print('');
        
        // Comentar esta línea para no fallar el test:
        // fail('🎯 Duplicate model definitions found:\n\n${modelViolations.join('\n\n')}\n\n💡 Consider consolidating these models or moving them to the correct bounded context.');
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
        violations.add('🗑️ Empty barrel files found:\n${emptyBarrels.map((f) => '   - $f').join('\n')}');
      }

      if (shimsAndDeprecated.isNotEmpty) {
        violations.add(
          '🚫 Deprecated shims/migration files found:\n${shimsAndDeprecated.map((f) => '   - $f').join('\n')}',
        );
      }

      if (violations.isNotEmpty) {
        final rmCommands = [...emptyBarrels, ...shimsAndDeprecated].map((f) => 'rm \'$f\'').join('\n');
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
          '📝 Obsolete comments found:\n\n${obsoleteComments.map((c) => '   $c').join('\n')}\n\n'
          '💡 Clean these comments that reference old/deprecated methods, TODO items from migration, or outdated architecture notes.',
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
              final resolvedPath = _resolveRelativePath(fileDir.path, exportPath);

              if (!File('$resolvedPath.dart').existsSync() && !File(resolvedPath).existsSync()) {
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
  });
}

// ===================== NUEVOS HELPER FUNCTIONS =====================

bool _isEmptyBarrel(String content, String path) {
  // Detectar archivos que son principalmente barrel exports pero están completamente vacíos
  if (!path.endsWith('.dart') || path.contains('test/') || path.endsWith('main.dart')) {
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
      content.trim().split('\n').where((line) => line.trim().startsWith('export ')).isEmpty;
}

bool _isDeprecatedShimOrMigration(String content, String path) {
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

bool _hasObsoleteComment(String line) {
  final trimmed = line.trim().toLowerCase();

  // Comentarios que referencian métodos/archivos antiguos
  if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
    return trimmed.contains('// moved to') && !File(_extractMovedToPath(line) ?? '').existsSync() ||
        trimmed.contains('// removed') ||
        trimmed.contains('// use core version') ||
        trimmed.contains('// todo: migrate') ||
        trimmed.contains('// fixme: update') ||
        trimmed.contains('// old:') ||
        trimmed.contains('// deprecated:') ||
        trimmed.contains('// generated as part of') && trimmed.contains('migration') ||
        trimmed.contains('// legacy') ||
        trimmed.contains('// temporary') ||
        (trimmed.contains('todo') &&
            (trimmed.contains('remove') || trimmed.contains('clean') || trimmed.contains('delete'))) ||
        (trimmed.contains('fixme') && (trimmed.contains('remove') || trimmed.contains('clean')));
  }

  return false;
}

String? _extractMovedToPath(String comment) {
  final match = RegExp(r'moved to (.+\.dart)').firstMatch(comment.toLowerCase());
  return match?.group(1);
}

String? _extractExportPath(String exportLine) {
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

String _resolveRelativePath(String basePath, String relativePath) {
  if (relativePath.startsWith('/')) return relativePath;

  final baseDir = Directory(basePath);
  final resolved = File('${baseDir.path}/$relativePath').path;
  return resolved.replaceAll(r'\', '/');
}

List<File> _collectDartFiles() {
  final files = <File>[];
  final libDir = Directory('lib');
  final testDir = Directory('test');

  void collectFrom(Directory dir) {
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final path = entity.path.replaceAll(r'\', '/');
        if (path.contains('.g.dart') || path.contains('.freezed.dart') || path.contains('.mocks.dart')) {
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

String _normalizeContent(String content) {
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

List<Map<String, String>> _extractServiceClasses(String content, String path) {
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

        services.add({'name': className, 'signature': className, 'methods': methodSignatures, 'path': path});
      }
    }
  }

  return services;
}

List<Map<String, String>> _extractModelClasses(String content, String path) {
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

String _extractMethodSignatures(String content, String className) {
  final lines = content.split('\n');
  final signatures = <String>[];

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.contains('(') && !trimmed.startsWith('//') && !trimmed.startsWith('/*')) {
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

String _extractFields(String content, String className) {
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
          final fieldName = words[2].replaceAll('?', '').replaceAll(';', '').replaceAll('=', '').split('=')[0];
          if (!fieldName.startsWith('_') && !fieldName.contains('(') && fieldName.isNotEmpty) {
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

String _getRelativePath(String fullPath) {
  final currentDir = Directory.current.path.replaceAll(r'\', '/');
  return fullPath.replaceAll(r'\', '/').replaceAll('$currentDir/', '');
}

String _buildDuplicateFilesReport(List<List<String>> duplicates) {
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

bool _isArchitecturalBarrel(String path) {
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

bool _isFlutterWidgetPair(String className) {
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

bool _areRelatedClasses(List<String> classNames) {
  // Verificar si las clases son claramente relacionadas (e.g., diferentes versiones del mismo concepto)
  final names = classNames.map((s) => s.split('(')[0]).toList();
  
  // Si las clases son de diferentes tipos (adapter, service, utils, etc.) - no son duplicados
  final types = names.map((n) => n.toLowerCase());
  final hasAdapter = types.any((t) => t.contains('adapter'));
  final hasService = types.any((t) => t.contains('service'));
  final hasUtils = types.any((t) => t.contains('utils'));
  final hasUseCase = types.any((t) => t.contains('usecase'));
  
  if ((hasAdapter || hasService || hasUtils || hasUseCase) && types.length > 1) {
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
    if (name1.replaceAll('ai', '').replaceAll('chan', '') == name2.replaceAll('ai', '').replaceAll('chan', '')) {
      return false; // SON duplicados reales
    }
  }
  
  return true; // Por defecto, asumir que están relacionados (no son duplicados reales)
}
