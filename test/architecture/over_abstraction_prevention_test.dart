import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Over-Abstraction Prevention Tests', () {
    test('no redundant adapter classes that only map 1:1 without logic', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final violations = <String>[];

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.path.contains('/adapters/')) {
          final content = file.readAsStringSync();

          // Skip files that clearly have substantial logic (indicators)
          if (_hasSubstantialLogic(content)) continue;

          // Look for adapter pattern: class XAdapter implements IInterface
          final adapterMatch = RegExp(
            r'class\s+(\w*Adapter)\s+implements\s+(\w+)',
          ).firstMatch(content);
          if (adapterMatch == null) continue;

          final adapterName = adapterMatch.group(1)!;
          final interfaceName = adapterMatch.group(2)!;

          // Check if this is just a 1:1 mapping adapter
          if (_isSimpleMappingAdapter(content, adapterName, interfaceName)) {
            violations.add(
              '${file.path}: $adapterName appears to only map 1:1 to $interfaceName without business logic',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Redundant mapping adapters detected (consider using core interfaces directly):\n${violations.join('\n')}',
      );
    });

    test('no orphaned domain interfaces (should have actual consumers)', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final domainInterfaces = <String>[];
      final allFiles = <File>[];

      // Collect all dart files and domain interfaces
      for (final file in libDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          allFiles.add(file);

          if (file.path.contains('/domain/') &&
              file.path.contains('interfaces')) {
            final content = file.readAsStringSync();
            final interfaces = RegExp(
              r'abstract\s+(?:interface\s+)?class\s+(\w+)',
            ).allMatches(content).map((final m) => m.group(1)!).toList();
            domainInterfaces.addAll(interfaces);
          }
        }
      }

      final orphanedInterfaces = <String>[];

      for (final interface in domainInterfaces) {
        bool hasConsumer = false;

        // Check if interface is used anywhere (implements, type annotation, etc.)
        for (final file in allFiles) {
          if (file.path.contains('/domain/') &&
              file.path.contains('interfaces')) {
            continue; // Skip definition file
          }

          final content = file.readAsStringSync();
          if (content.contains('implements $interface') ||
              content.contains(': $interface') ||
              content.contains('<$interface>') ||
              content.contains('$interface ') ||
              content.contains('($interface ')) {
            hasConsumer = true;
            break;
          }
        }

        if (!hasConsumer) {
          orphanedInterfaces.add(interface);
        }
      }

      // Allow some interfaces to be defined but not used yet (work in progress)
      final allowedOrphans = [
        'IRealtimeCallClient',
      ]; // Add interfaces that are intentionally unused
      final realOrphans = orphanedInterfaces
          .where((final i) => !allowedOrphans.contains(i))
          .toList();

      expect(
        realOrphans,
        isEmpty,
        reason:
            'Orphaned domain interfaces detected (no consumers found):\n${realOrphans.join('\n')}',
      );
    });

    test('no redundant export barrel files', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final barrelFiles = <String, List<String>>{};

      // Find all potential barrel files (files that mainly export)
      for (final file in libDir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = file.readAsStringSync();
          final exportLines = content
              .split('\n')
              .where((final line) => line.trim().startsWith('export '))
              .toList();

          if (exportLines.isNotEmpty) {
            // Only consider it a barrel if exports dominate the file content
            final nonCommentLines = content
                .split('\n')
                .where(
                  (final line) =>
                      line.trim().isNotEmpty && !line.trim().startsWith('//'),
                )
                .length;

            if (exportLines.length / nonCommentLines > 0.6) {
              barrelFiles[file.path] = exportLines;
            }
          }
        }
      }

      final redundantBarrels = <String>[];

      // Check for barrels that export the same things
      final exportGroups = <String, List<String>>{};
      barrelFiles.forEach((final path, final exports) {
        final sortedExports = exports.join(
          '|',
        ); // Create a signature from exports
        if (exportGroups.containsKey(sortedExports)) {
          exportGroups[sortedExports]!.add(path);
        } else {
          exportGroups[sortedExports] = [path];
        }
      });

      exportGroups.forEach((final signature, final paths) {
        if (paths.length > 1) {
          redundantBarrels.addAll(
            paths.skip(1),
          ); // Keep first, flag others as redundant
        }
      });

      expect(
        redundantBarrels,
        isEmpty,
        reason:
            'Redundant export barrel files detected:\n${redundantBarrels.join('\n')}',
      );
    });

    test('previously eliminated adapters should not reappear', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final bannedAdapters = [
        'voice_ai_adapter.dart',
        'voice_stt_adapter.dart',
        'voice_tts_adapter.dart',
      ];

      final violations = <String>[];

      for (final file in libDir.listSync(recursive: true)) {
        if (file is File) {
          final fileName = file.path.split('/').last;
          if (bannedAdapters.contains(fileName)) {
            violations.add(
              '${file.path}: Previously eliminated adapter has reappeared',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Previously eliminated redundant adapters have reappeared:\n${violations.join('\n')}',
      );
    });

    test('eliminated interfaces should not reappear in voice_interfaces.dart', () {
      final voiceInterfacesFile = File(
        'lib/voice/domain/interfaces/voice_interfaces.dart',
      );
      if (!voiceInterfacesFile.existsSync()) return;

      final content = voiceInterfacesFile.readAsStringSync();
      final bannedInterfaces = [
        'IVoiceAiService',
        'IVoiceSttService',
        'IVoiceTtsService',
      ];

      final violations = <String>[];

      for (final bannedInterface in bannedInterfaces) {
        // Check if interface is actually defined (not just mentioned in comments)
        final interfaceDefinitionPattern = RegExp(
          r'abstract\s+(?:interface\s+)?class\s+' + bannedInterface,
        );
        if (interfaceDefinitionPattern.hasMatch(content)) {
          violations.add(
            'Previously eliminated interface $bannedInterface has reappeared in voice_interfaces.dart',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Previously eliminated redundant interfaces have reappeared:\n${violations.join('\n')}',
      );
    });
  });
}

/// Checks if adapter has substantial business logic (not just 1:1 mapping)
bool _hasSubstantialLogic(final String content) {
  // Indicators of substantial logic
  final logicIndicators = [
    RegExp(r'if\s*\('), // Conditional logic
    RegExp(r'for\s*\('), // Loops
    RegExp(r'while\s*\('), // Loops
    RegExp(r'switch\s*\('), // Switch statements
    RegExp(r'try\s*\{'), // Error handling
    RegExp(r'await\s+\w+\.'), // Async operations
    RegExp(r'throw\s+'), // Exception throwing
    RegExp(r'\.map\s*\('), // Data transformation
    RegExp(r'\.filter\s*\('), // Data filtering
    RegExp(r'\.reduce\s*\('), // Data aggregation
    RegExp(r'debugPrint\s*\('), // Debugging/logging
    RegExp(r'[Vv]alidation'), // Validation logic
    RegExp(r'[Tt]ransform'), // Data transformation
  ];

  return logicIndicators.any((final pattern) => pattern.hasMatch(content));
}

/// Checks if adapter is just doing 1:1 method mapping
bool _isSimpleMappingAdapter(
  final String content,
  final String adapterName,
  final String interfaceName,
) {
  // Look for constructor that takes a single dependency
  final constructorPattern = RegExp(r'$adapterName\s*\(\s*this\._\w+\s*\)');
  if (!constructorPattern.hasMatch(content)) return false;

  // Look for methods that just delegate to the dependency
  final methodPattern = RegExp(
    r'@override\s+(?:Future<\w+>|\w+)\s+\w+\s*\([^)]*\)\s*(?:async\s*)?\{\s*return\s+(?:await\s+)?_\w+\.\w+\([^)]*\);\s*\}',
  );
  final delegationMethods = methodPattern.allMatches(content).length;

  // Look for total number of methods
  final allMethods = RegExp(r'@override').allMatches(content).length;

  // If most methods are simple delegation, it's likely a 1:1 mapping
  return delegationMethods > 0 && (delegationMethods / allMethods) > 0.7;
}
