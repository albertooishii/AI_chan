import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No test files declare local Fake classes outside test/fakes', () {
    final testDir = Directory('test');
    if (!testDir.existsSync()) return;

    final bad = <String, List<int>>{};
    final regex = RegExp(r'class\s+Fake[A-Za-z0-9_]*\b');

    for (final ent in testDir.listSync(recursive: true)) {
      if (ent is! File) continue;
      final path = ent.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      // allow files under test/fakes/ (canonical location) and test/disabled
      // match both absolute and relative paths by checking without a leading slash
      if (path.contains('test/fakes/') || path.contains('test/disabled/')) {
        continue;
      }

      final lines = ent.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          bad.putIfAbsent(path, () => []).add(i + 1);
        }
      }
    }

    if (bad.isNotEmpty) {
      final b = StringBuffer();
      b.writeln('Se encontraron clases Fake definidas fuera de `test/fakes/`:');
      bad.forEach((file, lines) {
        b.writeln(' - $file : líneas ${lines.join(", ")}');
      });
      b.writeln('\nPor favor mueve esos fakes a `test/fakes/` o elimínalos.');
      fail(b.toString());
    }
  });
}
