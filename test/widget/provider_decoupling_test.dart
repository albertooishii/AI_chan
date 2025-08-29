import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Widgets and presentation should not directly depend on Provider API', () {
    final repoRoot = Directory('lib');
    if (!repoRoot.existsSync()) return;

    // Collect dart files under presentation/ and widgets/ folders
    final files = repoRoot
        .listSync(recursive: true)
        .whereType<File>()
        // include Dart files under presentation/, widgets/ and shared/screen( s ) folders
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              (f.path.contains('/widgets/') ||
                  f.path.contains('/presentation/') ||
                  f.path.contains('/shared/screens/')),
        )
        .toList();

    final patterns = <String, RegExp>{
      'provider import': RegExp(r"package:provider/provider\.dart"),
      'Provider.of<': RegExp(r'Provider\.of<'),
      'context.watch<': RegExp(r'\bcontext\.watch<'),
      'context.read<': RegExp(r'\bcontext\.read<'),
      'context.select<': RegExp(r'\bcontext\.select<'),
      'Consumer<': RegExp(r'\bConsumer<'),
      'ChangeNotifierProvider<': RegExp(r'\bChangeNotifierProvider<'),
      'ChangeNotifierProvider.value': RegExp(r'ChangeNotifierProvider\.value'),
      'MultiProvider': RegExp(r'\bMultiProvider\b'),
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
        'Provider API usage found inside presentation/widgets code. Presentation and widget files must not call Provider API directly.',
      );
      buffer.writeln('Offending files and matches:');
      offenders.forEach((path, issues) {
        buffer.writeln('- $path');
        for (final it in issues) {
          buffer.writeln('    $it');
        }
      });
      buffer.writeln('If a screen needs a provider instance, pass it via constructor parameters from a parent widget.');
      fail(buffer.toString());
    }
  });
}
