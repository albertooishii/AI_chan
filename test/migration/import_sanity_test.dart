import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migration import sanity', () {
    test('no legacy core/models/index.dart imports in lib/', () {
      final dir = Directory('lib');
      final bad = <String>[];
      for (final f in dir.listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final s = f.readAsStringSync();
          if (s.contains("package:ai_chan/core/models/index.dart")) {
            bad.add(f.path);
          }
        }
      }
      expect(bad, isEmpty, reason: 'Found legacy imports: ${bad.join(', ')}');
    });

    test('no imports using alias "as models" in lib/', () {
      final dir = Directory('lib');
      final bad = <String>[];
      final re = RegExp(r'''import\s+['"][^'"]+['"]\s+as\s+models\b''');
      for (final f in dir.listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final s = f.readAsStringSync();
          if (re.hasMatch(s)) bad.add(f.path);
        }
      }
      expect(bad, isEmpty, reason: 'Found imports using alias "models": ${bad.join(', ')}');
    });
  });
}
