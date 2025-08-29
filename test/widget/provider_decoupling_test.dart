import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Widgets should not directly depend on Provider API', () {
    final repoRoot = Directory('lib');
    if (!repoRoot.existsSync()) return;

    final files = repoRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && f.path.contains('/widgets/'))
        .toList();

    final patterns = <String, RegExp>{
      'Provider.of<': RegExp(r'Provider\.of<'),
      'context.watch<': RegExp(r'\bcontext\.watch<'),
      'context.read<': RegExp(r'\bcontext\.read<'),
      'context.select<': RegExp(r'\bcontext\.select<'),
      'Consumer<': RegExp(r'Consumer<'),
      'ChangeNotifierProvider<': RegExp(r'ChangeNotifierProvider<'),
      'provider import': RegExp(r"package:provider/provider\.dart"),
    };

    final Map<String, List<String>> offenders = {};

    for (final file in files) {
      final content = file.readAsStringSync();
      final lines = content.split(RegExp('\r?\n'));
      final List<String> issues = [];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final entry in patterns.entries) {
          if (entry.value.hasMatch(line)) {
            issues.add('Line ${i + 1}: contains "${entry.key}" -> ${line.trim()}');
          }
        }
      }
      if (issues.isNotEmpty) offenders[file.path] = issues;
    }

    if (offenders.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln(
        'Found Provider usage in widget files. Widgets should be UI-only and receive callbacks/data from callers.',
      );
      buffer.writeln('Offending files and matches:');
      offenders.forEach((path, issues) {
        buffer.writeln('- $path');
        for (final it in issues) {
          buffer.writeln('    $it');
        }
      });
      fail(buffer.toString());
    }
  });
}
