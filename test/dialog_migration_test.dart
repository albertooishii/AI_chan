import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No direct showDialog usages in lib (use showAppDialog)', () {
    final dir = Directory('lib');
    final badFiles = <String>[];
    // Match showDialog with optional generic parameters, e.g. showDialog<String>( ... )
    final pattern = RegExp(r"\bshowDialog(?:\s*<[^>]*>)?\s*\(");

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        // compute a repo-relative path without importing package:path
        final parts = entity.path.split(Platform.pathSeparator);
        final libIndex = parts.indexOf('lib');
        String rel;
        if (libIndex != -1) {
          // join using forward slash for a stable comparison across OSes
          rel = parts.sublist(libIndex).join('/');
        } else {
          // fallback: normalize separators to forward slash
          rel = entity.path.replaceAll(Platform.pathSeparator, '/');
        }
        // allow the utilities file that intentionally wraps showDialog
        if (rel == 'lib/shared/utils/dialog_utils.dart') continue;
        final content = entity.readAsStringSync();
        if (pattern.hasMatch(content)) {
          badFiles.add(rel);
        }
      }
    }

    expect(
      badFiles,
      isEmpty,
      reason: 'Found direct showDialog usages in files: ${badFiles.join(', ')}',
    );
  });
}
