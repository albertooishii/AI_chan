import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _lineInfo(String content, int index) {
  final before = content.substring(0, index);
  final line = before.split('\n').length;
  return 'line $line';
}

void main() {
  test('no direct runtime instantiation outside runtime_factory', () {
    final libDir = Directory('lib');
    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) =>
              !f.path.endsWith('lib/core/runtime_factory.dart') &&
              !f.path.endsWith('lib/shared/services/ai_runtime_provider.dart'),
        )
        .toList();

    final patterns = [RegExp(r'\bOpenAIService\s*\('), RegExp(r'\bGeminiService\s*\(')];
    final offenders = <String>[];

    for (final f in files) {
      final content = f.readAsStringSync();
      for (final p in patterns) {
        final m = p.firstMatch(content);
        if (m != null) {
          offenders.add('${f.path}:${_lineInfo(content, m.start)} -> ${p.pattern}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Direct runtime instantiations found outside runtime_factory:\n${offenders.join('\n')}',
    );
  });
}
