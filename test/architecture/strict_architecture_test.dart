import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('🚨 Strict Architecture Tests - FAIL ON VIOLATIONS', () {
    late Directory libDir;
    late List<FileSystemEntity> dartFiles;
    late List<String> sharedExports;

    setUpAll(() async {
      libDir = Directory('lib');
      if (!libDir.existsSync()) {
        throw Exception('lib directory not found');
      }

      // Get all dart files
      dartFiles = libDir
          .listSync(recursive: true)
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      // Parse shared.dart exports
      final sharedFile = File('lib/shared.dart');
      if (sharedFile.existsSync()) {
        final content = await sharedFile.readAsString();
        sharedExports = [];
        for (final line in content.split('\n')) {
          if (line.trim().startsWith('export ')) {
            // Extract path from export statement
            final startQuote = line.indexOf("'");
            final endQuote = line.lastIndexOf("'");
            if (startQuote != -1 && endQuote != -1 && endQuote > startQuote) {
              final exportPath = line.substring(startQuote + 1, endQuote);
              sharedExports.add(exportPath);
            }
          }
        }
      } else {
        sharedExports = [];
      }
    });

    test('🚨 CRITICAL: No cross-context dependencies allowed', () async {
      final List<String> crossContextViolations = [];
      final contexts = ['chat', 'onboarding', 'voice', 'core'];

      for (final file in dartFiles) {
        if (file is File) {
          final content = await file.readAsString();
          final lines = content.split('\n');

          // Determine current context
          String? currentContext;
          for (final context in contexts) {
            if (file.path.contains('lib/$context/')) {
              currentContext = context;
              break;
            }
          }

          if (currentContext != null) {
            // Check for imports to other contexts
            for (int i = 0; i < lines.length; i++) {
              final line = lines[i].trim();
              if (line.startsWith('import ') &&
                  line.contains('package:ai_chan/')) {
                for (final otherContext in contexts) {
                  if (otherContext != currentContext &&
                      line.contains('package:ai_chan/$otherContext/')) {
                    crossContextViolations.add(
                      '${file.path}:${i + 1}: $currentContext → $otherContext',
                    );
                  }
                }
              }
            }
          }
        }
      }

      if (crossContextViolations.isNotEmpty) {
        final message =
            '''
🚨 CRITICAL ARCHITECTURE VIOLATION: Cross-context dependencies detected!

Found ${crossContextViolations.length} violations:
${crossContextViolations.take(10).join('\n')}
${crossContextViolations.length > 10 ? '... and ${crossContextViolations.length - 10} more' : ''}

💡 FIX: Move shared functionality to shared/ or use proper dependency injection
''';
        fail(message);
      }
    });

    test(
      '🚨 CRITICAL: Presentation layer cannot import infrastructure directly',
      () async {
        final List<String> presentationInfraViolations = [];

        for (final file in dartFiles) {
          if (file is File && file.path.contains('/presentation/')) {
            final content = await file.readAsString();
            final lines = content.split('\n');

            for (int i = 0; i < lines.length; i++) {
              final line = lines[i].trim();
              if (line.startsWith('import ') &&
                  line.contains('package:ai_chan/') &&
                  line.contains('/infrastructure/')) {
                presentationInfraViolations.add('${file.path}:${i + 1}: $line');
              }
            }
          }
        }

        if (presentationInfraViolations.isNotEmpty) {
          final message =
              '''
🚨 ARCHITECTURE VIOLATION: Presentation importing infrastructure directly!

Found ${presentationInfraViolations.length} violations:
${presentationInfraViolations.take(10).join('\n')}
${presentationInfraViolations.length > 10 ? '... and ${presentationInfraViolations.length - 10} more' : ''}

💡 FIX: Use shared.dart or application layer instead of direct infrastructure imports
''';
          fail(message);
        }
      },
    );

    test('⚠️  WARNING: Should use shared.dart instead of direct imports', () async {
      final List<String> directImportViolations = [];

      // Find what's already exported in shared.dart
      final Set<String> exportedPaths = sharedExports.toSet();

      for (final file in dartFiles) {
        if (file is File) {
          final content = await file.readAsString();
          final lines = content.split('\n');

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.startsWith('import ') &&
                line.contains('package:ai_chan/shared/')) {
              // Extract the imported path using string parsing
              final packageStart = line.indexOf('package:ai_chan/');
              if (packageStart != -1) {
                final pathStart = packageStart + 'package:ai_chan/'.length;
                final pathEnd = line.indexOf("'", pathStart);
                if (pathEnd == -1) {
                  final pathEnd2 = line.indexOf('"', pathStart);
                  if (pathEnd2 != -1) {
                    final importedPath = line.substring(pathStart, pathEnd2);

                    // Check if this path is exported in shared.dart
                    for (final exportedPath in exportedPaths) {
                      if (importedPath == exportedPath) {
                        directImportViolations.add(
                          '${file.path}: Direct import of $importedPath (use shared.dart instead)',
                        );
                        break;
                      }
                    }
                  }
                } else {
                  final importedPath = line.substring(pathStart, pathEnd);

                  // Check if this path is exported in shared.dart
                  for (final exportedPath in exportedPaths) {
                    if (importedPath == exportedPath) {
                      directImportViolations.add(
                        '${file.path}: Direct import of $importedPath (use shared.dart instead)',
                      );
                      break;
                    }
                  }
                }
              }
            }
          }
        }
      }

      // This is a WARNING test - only fail if violations are too many
      if (directImportViolations.length > 250) {
        final message =
            '''
⚠️  TOO MANY direct import violations: ${directImportViolations.length}

Found ${directImportViolations.take(5).join('\n')}
... and ${directImportViolations.length - 5} more

💡 FIX: Use shared.dart instead of direct imports
''';
        fail(message);
      }
    });

    test('🔍 INFO: Interface duplication detection (non-blocking)', () async {
      final Map<String, List<String>> interfaceFiles = {};

      for (final file in dartFiles) {
        if (file is File) {
          final content = await file.readAsString();
          final lines = content.split('\n');

          for (final line in lines) {
            if (line.contains('abstract class I') ||
                line.contains('abstract interface class I')) {
              // Extract interface name using string parsing
              final words = line.split(' ');
              for (int i = 0; i < words.length; i++) {
                if (words[i] == 'class' && i + 1 < words.length) {
                  final className = words[i + 1];
                  if (className.startsWith('I') && className.length > 1) {
                    interfaceFiles.putIfAbsent(className, () => []);
                    if (!interfaceFiles[className]!.contains(file.path)) {
                      interfaceFiles[className]!.add(file.path);
                    }
                  }
                  break;
                }
              }
            }
          }
        }
      }

      final duplicates = interfaceFiles.entries
          .where((entry) => entry.value.length > 1)
          .toList();

      if (duplicates.isNotEmpty) {
        print('''
🎭 INTERFACE DUPLICATION DETECTED (${duplicates.length} duplicates):
${duplicates.map((e) => '   📝 ${e.key}: ${e.value.length} definitions').join('\n')}

💡 RECOMMENDATION: Consolidate duplicates in shared/
''');
      }
    });
  });
}
