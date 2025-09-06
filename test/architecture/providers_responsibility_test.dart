import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Providers (ChangeNotifier) must not call infrastructure APIs', () {
    final libDir = Directory('lib');
    if (!libDir.existsSync()) return;

    final violations = <String>[];

    final infraNames = {
      'PrefsUtils',
      'IAAppearanceGenerator',
      'IAAvatarGenerator',
      'ProviderPersistUtils',
      'showAppDialog',
      'File',
      // 'di' matched separately to avoid accidental matches inside words
    };

    final classRegex = RegExp(r'class\s+(\w+)\s+extends\s+ChangeNotifier');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;

      final content = entity.readAsStringSync();

      for (final match in classRegex.allMatches(content)) {
        final className = match.group(1)!;
        // find class body by locating the opening brace after the match
        final startIndex = content.indexOf('{', match.end);
        if (startIndex == -1) continue;
        var idx = startIndex + 1;
        var depth = 1;
        while (idx < content.length && depth > 0) {
          final char = content[idx];
          if (char == '{') depth++;
          if (char == '}') depth--;
          idx++;
        }
        if (depth != 0) continue; // malformed file, skip
        final body = content.substring(startIndex, idx);

        final found = <String>{};

        for (final infra in infraNames) {
          final wordRegex = RegExp('\\b${RegExp.escape(infra)}\\b');
          if (wordRegex.hasMatch(body)) found.add(infra);
        }

        // Detect explicit DI usage: alias usage `di.` or imports like '.../di.dart' or 'as di'
        if (RegExp(r'\\bdi\\.').hasMatch(body) ||
            RegExp(r'as\s+di\b').hasMatch(body)) {
          found.add('di');
        }

        if (found.isNotEmpty) {
          violations.add(
            '$path -> $className: infra usage -> ${found.join(', ')}',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Providers using infra detected:\n${violations.join('\n')}',
    );
  });
}
