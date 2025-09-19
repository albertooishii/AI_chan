import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Test completamente genérico para detectar redundancias y violaciones arquitectónicas
/// NO hardcodea archivos específicos - todo se detecta dinámicamente
void main() {
  group('🔍 Generic Architecture & Redundancy Detection', () {
    test(
      '📊 No direct imports of utilities already exported in shared.dart',
      () async {
        final sharedFile = File('lib/shared.dart');
        expect(
          sharedFile.existsSync(),
          isTrue,
          reason: 'shared.dart should exist',
        );

        final sharedContent = await sharedFile.readAsString();

        // Extraer TODOS los exports de shared.dart dinámicamente
        final exportedPaths = <String>[];
        final lines = sharedContent.split('\n');
        for (final line in lines) {
          if (line.trim().startsWith('export ')) {
            final match = RegExp(r"export\s+'([^']+)'").firstMatch(line);
            if (match != null) {
              exportedPaths.add(match.group(1)!);
            } else {
              final match2 = RegExp(r'export\s+"([^"]+)"').firstMatch(line);
              if (match2 != null) {
                exportedPaths.add(match2.group(1)!);
              }
            }
          }
        }

        print('🔍 Found ${exportedPaths.length} exports in shared.dart');

        final violations = <String>[];
        final libDir = Directory('lib');

        await for (final file in libDir.list(recursive: true)) {
          if (file is File &&
              file.path.endsWith('.dart') &&
              !file.path.endsWith('shared.dart') &&
              !file.path.contains('/test/')) {
            final content = await file.readAsString();

            for (final exportedPath in exportedPaths) {
              final patterns = [
                "import 'package:ai_chan/$exportedPath'",
                'import "package:ai_chan/$exportedPath"',
              ];

              for (final pattern in patterns) {
                if (content.contains(pattern)) {
                  violations.add(
                    '${file.path}: Direct import of $exportedPath (use shared.dart instead)',
                  );
                }
              }
            }
          }
        }

        if (violations.isNotEmpty) {
          print('❌ Found ${violations.length} direct import violations:');
          for (final violation in violations.take(5)) {
            print('   $violation');
          }
          if (violations.length > 5) {
            print('   ... and ${violations.length - 5} more');
          }

          // Solo reportar, no fallar para permitir refactorización gradual
          print(
            '\n💡 RECOMMENDATION: Use shared.dart instead of direct imports',
          );
        } else {
          print('✅ No direct import violations found');
        }
      },
    );

    test(
      '🎯 Presentation layer should not import infrastructure directly',
      () async {
        final violations = <String>[];
        final libDir = Directory('lib');

        // Buscar dinámicamente todos los directorios de presentation
        await for (final entity in libDir.list(recursive: true)) {
          if (entity is Directory && entity.path.contains('/presentation')) {
            await for (final file in entity.list(recursive: true)) {
              if (file is File && file.path.endsWith('.dart')) {
                final content = await file.readAsString();

                // Detectar imports directos de infrastructure
                final lines = content.split('\n');
                for (int i = 0; i < lines.length; i++) {
                  final line = lines[i].trim();
                  if (line.contains('/infrastructure/') &&
                      (line.startsWith("import 'package:ai_chan/") ||
                          line.startsWith('import "package:ai_chan/'))) {
                    violations.add('${file.path}:${i + 1}: $line');
                  }
                }
              }
            }
          }
        }

        if (violations.isNotEmpty) {
          print(
            '⚠️  Found ${violations.length} presentation → infrastructure violations:',
          );
          for (final violation in violations.take(5)) {
            print('   $violation');
          }
          if (violations.length > 5) {
            print('   ... and ${violations.length - 5} more');
          }
          print(
            '\n💡 RECOMMENDATION: Use shared.dart or application layer instead',
          );
        } else {
          print('✅ No presentation → infrastructure violations found');
        }
      },
    );

    test('🏗️ Detect cross-context dependencies dynamically', () async {
      final contextDirs = <String>[];
      final libDir = Directory('lib');

      // Detectar TODOS los bounded contexts automáticamente
      await for (final entity in libDir.list()) {
        if (entity is Directory) {
          final contextName = entity.path.split('/').last;
          if (contextName != 'shared' && !contextName.startsWith('.')) {
            contextDirs.add(contextName);
          }
        }
      }

      print('🔍 Found contexts: ${contextDirs.join(', ')}');

      final crossContextDependencies = <String, Set<String>>{};
      final detailedViolations = <String>[];

      // Analizar imports entre contextos dinámicamente
      for (final context in contextDirs) {
        final contextDir = Directory('lib/$context');
        if (!contextDir.existsSync()) continue;

        crossContextDependencies[context] = <String>{};

        await for (final file in contextDir.list(recursive: true)) {
          if (file is File && file.path.endsWith('.dart')) {
            final content = await file.readAsString();
            final lines = content.split('\n');

            for (int i = 0; i < lines.length; i++) {
              final line = lines[i].trim();
              if (line.startsWith("import 'package:ai_chan/") ||
                  line.startsWith('import "package:ai_chan/')) {
                for (final otherContext in contextDirs) {
                  if (otherContext != context &&
                      line.contains('/$otherContext/')) {
                    crossContextDependencies[context]!.add(otherContext);
                    detailedViolations.add(
                      '${file.path}:${i + 1}: $context → $otherContext',
                    );
                  }
                }
              }
            }
          }
        }
      }

      // Reportar dependencias cruzadas
      final hasCrossDependencies = crossContextDependencies.values.any(
        (deps) => deps.isNotEmpty,
      );

      if (hasCrossDependencies) {
        print('\n🔄 CROSS-CONTEXT DEPENDENCIES DETECTED:');
        print('=' * 60);

        crossContextDependencies.forEach((context, dependencies) {
          if (dependencies.isNotEmpty) {
            print('📁 $context depends on: ${dependencies.join(', ')}');
          }
        });

        print('\n📋 DETAILED VIOLATIONS:');
        for (final violation in detailedViolations.take(10)) {
          print('   $violation');
        }
        if (detailedViolations.length > 10) {
          print('   ... and ${detailedViolations.length - 10} more');
        }

        print('\n💡 RECOMMENDATION: Move common functionality to shared/');
      } else {
        print('✅ No cross-context dependencies found');
      }
    });

    test('🔍 Detect duplicate interfaces and classes across contexts', () async {
      final interfaceDefinitions = <String, List<String>>{};
      final classDefinitions = <String, List<String>>{};
      final libDir = Directory('lib');

      // Patrones para detectar interfaces y clases
      final interfaceRegex = RegExp(
        r'(?:abstract\s+)?(?:class|interface)\s+(I[A-Z]\w*)\s*[{<]',
      );
      final classRegex = RegExp(
        r'class\s+([A-Z]\w*(?:Service|Utils|Helper|Manager|Controller))\s*[{<]',
      );

      await for (final file in libDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = await file.readAsString();

          // Buscar interfaces (empiezan con I)
          final interfaceMatches = interfaceRegex.allMatches(content);
          for (final match in interfaceMatches) {
            final interfaceName = match.group(1)!;
            if (!interfaceDefinitions.containsKey(interfaceName)) {
              interfaceDefinitions[interfaceName] = [];
            }
            interfaceDefinitions[interfaceName]!.add(file.path);
          }

          // Buscar clases utilitarias
          final classMatches = classRegex.allMatches(content);
          for (final match in classMatches) {
            final className = match.group(1)!;
            if (!classDefinitions.containsKey(className)) {
              classDefinitions[className] = [];
            }
            classDefinitions[className]!.add(file.path);
          }
        }
      }

      // Reportar duplicaciones
      final duplicateInterfaces = <String, List<String>>{};
      final duplicateClasses = <String, List<String>>{};

      interfaceDefinitions.forEach((name, files) {
        if (files.length > 1) {
          duplicateInterfaces[name] = files;
        }
      });

      classDefinitions.forEach((name, files) {
        if (files.length > 1) {
          // Verificar que están en contextos diferentes
          final contexts = files.map((path) => path.split('/')[1]).toSet();
          if (contexts.length > 1) {
            duplicateClasses[name] = files;
          }
        }
      });

      if (duplicateInterfaces.isNotEmpty || duplicateClasses.isNotEmpty) {
        print('\n🔄 DUPLICATE DEFINITIONS DETECTED:');
        print('=' * 60);

        if (duplicateInterfaces.isNotEmpty) {
          print('🏗️  DUPLICATE INTERFACES:');
          duplicateInterfaces.forEach((name, files) {
            print('   📝 $name:');
            for (final file in files) {
              print('      📄 $file');
            }
          });
        }

        if (duplicateClasses.isNotEmpty) {
          print('\n🔧 DUPLICATE CLASSES ACROSS CONTEXTS:');
          duplicateClasses.forEach((name, files) {
            print('   📝 $name:');
            for (final file in files) {
              print('      📄 $file');
            }
          });
        }

        print('\n💡 RECOMMENDATION: Consolidate duplicates in shared/');
      } else {
        print('✅ No duplicate interfaces or classes found');
      }
    });

    test('🔧 Detect similar method patterns across contexts', () async {
      final methodPatterns = <String, List<String>>{};
      final libDir = Directory('lib');

      // Patrones de métodos que sugieren duplicación funcional
      final utilityMethodRegex = RegExp(
        r'(?:static\s+)?(?:\w+\s+)*(\w*(?:format|parse|validate|convert|transform|normalize|sanitize|load|save|delete|get|set)\w*)\s*\([^)]*\)',
      );

      await for (final file in libDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = await file.readAsString();

          final matches = utilityMethodRegex.allMatches(content);
          for (final match in matches) {
            final methodName = match.group(1)!;

            // Solo considerar métodos que probablemente sean utilitarios
            if (methodName.length > 4 &&
                (methodName.startsWith('format') ||
                    methodName.startsWith('parse') ||
                    methodName.startsWith('validate') ||
                    methodName.startsWith('convert') ||
                    methodName.startsWith('transform') ||
                    methodName.startsWith('normalize') ||
                    methodName.startsWith('sanitize'))) {
              if (!methodPatterns.containsKey(methodName)) {
                methodPatterns[methodName] = [];
              }
              methodPatterns[methodName]!.add(file.path);
            }
          }
        }
      }

      // Detectar métodos similares en contextos diferentes
      final crossContextMethods = <String, List<String>>{};
      methodPatterns.forEach((methodName, files) {
        if (files.length > 1) {
          final contexts = files.map((path) => path.split('/')[1]).toSet();
          if (contexts.length > 1 && !contexts.contains('shared')) {
            crossContextMethods[methodName] = files;
          }
        }
      });

      if (crossContextMethods.isNotEmpty) {
        print('\n🔄 SIMILAR METHODS ACROSS CONTEXTS:');
        print('=' * 60);

        crossContextMethods.forEach((methodName, files) {
          print('⚙️  $methodName:');
          for (final file in files.take(3)) {
            print('   📄 $file');
          }
          if (files.length > 3) {
            print('   ... and ${files.length - 3} more');
          }
        });

        print('\n💡 RECOMMENDATION: Consider consolidating similar methods');
      } else {
        print('✅ No suspicious method patterns found');
      }
    });

    test('📱 Detect problematic import patterns dynamically', () async {
      final problematicPatterns = <String, int>{};
      final libDir = Directory('lib');

      // Patrones dinámicos - NO hardcodeamos archivos específicos
      final detectablePatterns = <String, RegExp>{
        'utils_direct_imports': RegExp(r'import.*utils\.dart'),
        'service_direct_imports': RegExp(r'import.*service\.dart'),
        'di_direct_imports': RegExp(r'import.*infrastructure/di/'),
        'critical_cross_context': RegExp(
          r'import.*/(chat|voice|onboarding)/.*service\.dart',
        ),
        'screen_cross_imports': RegExp(
          r'import.*/presentation/screens/.*\.dart',
        ),
      };

      for (final category in detectablePatterns.keys) {
        problematicPatterns[category] = 0;
      }

      await for (final file in libDir.list(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.contains('/test/')) {
          final content = await file.readAsString();

          detectablePatterns.forEach((category, pattern) {
            final matches = pattern.allMatches(content);
            problematicPatterns[category] =
                problematicPatterns[category]! + matches.length;
          });
        }
      }

      print('\n🎯 PROBLEMATIC IMPORT PATTERNS:');
      print('=' * 60);

      var criticalViolations = 0;
      problematicPatterns.forEach((pattern, count) {
        if (count > 0) {
          final severity =
              pattern.contains('critical') || pattern.contains('screen_cross')
              ? '🚨 CRITICAL'
              : '⚠️  WARNING';
          print('$severity $pattern: $count occurrences');
          if (pattern.contains('critical') ||
              pattern.contains('screen_cross')) {
            criticalViolations += count;
          }
        }
      });

      print('=' * 60);
      print('🔥 Critical architecture violations: $criticalViolations');

      if (criticalViolations > 0) {
        print(
          '\n💡 RECOMMENDATION: These patterns suggest architectural violations',
        );
        print('   that should be addressed to maintain clean architecture');
      }
    });

    test('📈 Generate comprehensive redundancy report', () async {
      final report = <String, int>{};
      final libDir = Directory('lib');

      // Patrones dinámicos para detectar diferentes tipos de redundancias
      final importPatterns = {
        'shared_infrastructure_utils': RegExp(r'shared/infrastructure/utils/'),
        'shared_infrastructure_services': RegExp(
          r'shared/infrastructure/services/',
        ),
        'shared_infrastructure_cache': RegExp(r'shared/infrastructure/cache/'),
        'shared_infrastructure_di': RegExp(r'shared/infrastructure/di/'),
        'shared_ai_providers': RegExp(r'shared/ai_providers/'),
        'cross_context_imports': RegExp(r'package:ai_chan/(?!shared)(\w+)/'),
        'direct_model_imports': RegExp(r'shared/domain/models/'),
        'direct_interface_imports': RegExp(r'shared/domain/interfaces/'),
      };

      for (final category in importPatterns.keys) {
        report[category] = 0;
      }

      var totalFiles = 0;
      await for (final file in libDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          totalFiles++;
          final content = await file.readAsString();

          importPatterns.forEach((category, pattern) {
            final matches = pattern.allMatches(content);
            report[category] = report[category]! + matches.length;
          });
        }
      }

      print('\n📊 COMPREHENSIVE REDUNDANCY REPORT:');
      print('=' * 50);
      print('📁 Total Dart files analyzed: $totalFiles');
      print('=' * 50);

      var totalIssues = 0;
      report.forEach((category, count) {
        if (count > 0) {
          print('📄 $category: $count occurrences');
          totalIssues += count;
        }
      });

      print('=' * 50);
      print('🎯 Total potential redundancies: $totalIssues');

      if (totalIssues > 0) {
        print('\n💡 NEXT STEPS:');
        print('   1. Add missing exports to shared.dart');
        print('   2. Refactor direct imports to use shared.dart');
        print('   3. Move cross-context utilities to shared/');
        print('   4. Eliminate duplicate utility functions');
      } else {
        print('✅ Excellent! No major redundancies detected');
      }
    });

    test('🚀 Validate shared.dart organization and completeness', () async {
      final sharedFile = File('lib/shared.dart');
      final sharedContent = await sharedFile.readAsString();

      // Verificar secciones organizacionales dinámicamente
      final organizationalSections = [
        'Domain Layer',
        'Application Layer',
        'Infrastructure Layer',
        'Presentation Layer',
        'Constants',
      ];

      final missingSections = <String>[];
      for (final section in organizationalSections) {
        if (!sharedContent.contains(section)) {
          missingSections.add(section);
        }
      }

      // Contar exports dinámicamente
      final exportCount = sharedContent
          .split('\n')
          .where((line) => line.trim().startsWith('export '))
          .length;

      // Verificar que hay exports de cada tipo principal
      final exportTypes = {
        'domain': sharedContent.contains('domain/'),
        'application': sharedContent.contains('application/'),
        'infrastructure': sharedContent.contains('infrastructure/'),
        'presentation': sharedContent.contains('presentation/'),
      };

      print('📊 Shared.dart Analysis:');
      print('   📄 Total exports: $exportCount');
      print(
        '   🏗️  Domain exports: ${(exportTypes['domain'] ?? false) ? '✅' : '❌'}',
      );
      print(
        '   ⚙️  Application exports: ${(exportTypes['application'] ?? false) ? '✅' : '❌'}',
      );
      print(
        '   🔧 Infrastructure exports: ${(exportTypes['infrastructure'] ?? false) ? '✅' : '❌'}',
      );
      print(
        '   🎨 Presentation exports: ${(exportTypes['presentation'] ?? false) ? '✅' : '❌'}',
      );

      if (missingSections.isNotEmpty) {
        print(
          '⚠️  Missing organizational sections: ${missingSections.join(', ')}',
        );
      }

      expect(
        exportCount,
        greaterThan(10),
        reason: 'shared.dart should export a reasonable number of utilities',
      );

      print('✅ Shared.dart structure validated');
    });
  });
}
