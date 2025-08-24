import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test detector that scans the repository for raw network usage patterns
/// (HttpClient, WebSocket.connect, IOWebSocketChannel.connect, Socket.connect)
/// and fails the test if any are found in non-test Dart files.
///
/// To deliberately allow network usage in a file, add the comment:
///   // allow-network
/// to the top of the file.
void main() {
  test('No raw network APIs used directly in source code (must use fakes)', () {
    final repoRoot = Directory.current;
    final patterns = <String, RegExp>{
      'HttpClient(': RegExp(r'\bHttpClient\s*\('),
      'WebSocket.connect(': RegExp(r'WebSocket\.connect\s*\('),
      'IOWebSocketChannel.connect(': RegExp(r'IOWebSocketChannel\.connect\s*\('),
      'Socket.connect(': RegExp(r'Socket\.connect\s*\('),
      'new Socket(': RegExp(r'new\s+Socket\s*\('),
    };

    final offenders = <String, List<Map<String, dynamic>>>{};

    for (final entity in repoRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;
      // skip tests and generated/build folders
      if (path.contains('/test/') || path.contains('/.dart_tool/') || path.contains('/build/')) {
        continue;
      }

      final content = entity.readAsStringSync();
      // allowlist marker for intentional network-using files
      if (content.contains('// allow-network')) continue;

      final lines = content.split(RegExp(r'\r?\n'));
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final entry in patterns.entries) {
          if (entry.value.hasMatch(line)) {
            offenders.putIfAbsent(path, () => []).add({'line': i + 1, 'pattern': entry.key, 'snippet': line.trim()});
          }
        }
      }
    }

    if (offenders.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('Detected raw network API usages in source files:');
      offenders.forEach((path, issues) {
        buffer.writeln('\n$path:');
        for (final it in issues) {
          buffer.writeln('  line ${it['line']}: [${it['pattern']}] ${it['snippet']}');
        }
      });
      buffer.writeln(
        '\nIf these are intentional, add a top-level comment "// allow-network" to the file.'
        ' Otherwise, wrap network usage behind an injectable client or register a test factory in tests.',
      );

      fail(buffer.toString());
    }
  });
}
