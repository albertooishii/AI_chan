import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no direct runtime instantiations (OpenAIService/GeminiService) in lib/', () {
    final root = Directory('lib');
    final disallowed = RegExp(r'\b(OpenAIService)\s*\(|\b(GeminiService)\s*\(');
    final allowedPaths = {
      'lib/core/runtime_factory.dart', // central factory allowed to instantiate
    };

    final matches = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final rel = entity.path.replaceAll('\\', '/');
        if (allowedPaths.contains(rel)) continue;
        final content = entity.readAsStringSync();
        if (disallowed.hasMatch(content)) matches.add(rel);
      }
    }

    expect(matches, isEmpty, reason: 'Found direct runtime instantiations in these files: ${matches.join(', ')}');
  });
}
