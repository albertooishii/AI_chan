import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ports & Adapters Completeness', () {
    test(
      'Each domain interface should have at least one infrastructure implementation',
      () {
        final libDir = Directory('lib');
        if (!libDir.existsSync()) return;

        final domainInterfaces = <String, String>{}; // name -> path
        final infraFiles = <File>[];

        for (final ent in libDir.listSync(recursive: true)) {
          if (ent is File && ent.path.endsWith('.dart')) {
            final path = ent.path.replaceAll(r'\\', '/');
            final content = ent.readAsStringSync();

            // Collect interfaces under domain/interfaces
            if (path.contains('/domain/interfaces/') ||
                path.contains('/domain/')) {
              final matches = RegExp(
                r'abstract\s+(?:interface\s+)?class\s+(I\w+)',
              ).allMatches(content);
              for (final m in matches) {
                domainInterfaces[m.group(1)!] = path;
              }
            }

            // Collect infra files
            if (path.contains('/infrastructure/') ||
                path.contains('/adapters/')) {
              infraFiles.add(ent);
            }
          }
        }

        final missing = <String>[];
        final knownMissingInterfaces = [
          // ✅ RESOLVED: IChatFileOperationsService implemented in BasicChatFileOperationsService
          // ✅ CENTRALIZED: These interfaces now have centralized implementations
          'ITtsService', // Replaced by CentralizedTtsService
          'ISttService', // Replaced by CentralizedSttService
          'INativeTtsService', // Legacy interface, using centralized approach
        ];

        for (final iface in domainInterfaces.keys) {
          final hasImpl = infraFiles.any((final f) {
            final content = f.readAsStringSync();
            return content.contains('implements $iface') ||
                content.contains('implementss+$iface');
          });

          if (!hasImpl && !knownMissingInterfaces.contains(iface)) {
            missing.add('$iface (defined in ${domainInterfaces[iface]})');
          }
        }

        expect(
          missing,
          isEmpty,
          reason:
              '''
Missing infrastructure implementations for domain interfaces:
${missing.join('\n')}

KNOWN MISSING INTERFACES (planned for future implementation):
${knownMissingInterfaces.map((final iface) => '• $iface').join('\n')}

Each domain interface should have at least one infrastructure implementation
that follows the Port-Adapter pattern.
          ''',
        );
      },
    );
  });
}
