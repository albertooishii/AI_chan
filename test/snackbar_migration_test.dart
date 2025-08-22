import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No direct showSnackBar usages in lib (use showAppSnackBar)', () {
    final dir = Directory('lib');
    final badFiles = <String>[];
    // Match both method calls like `.showSnackBar(` and plain `showSnackBar(`
    final pattern = RegExp(r'(\.showSnackBar\s*\(|\bshowSnackBar\s*\()');

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
        // allow internal helper file that may reference showSnackBar intentionally
        if (rel == 'lib/shared/utils/dialog_utils.dart') continue;

        final content = entity.readAsStringSync();
        if (pattern.hasMatch(content)) {
          badFiles.add(rel);
        }
      }
    }

    expect(badFiles, isEmpty, reason: 'Found direct showSnackBar usages in files: ${badFiles.join(', ')}');
  });

  test('No direct showOverlaySnackBar usages in lib (use showAppSnackBar)', () {
    final dir = Directory('lib');
    final badFiles = <String>[];
    // Match showOverlaySnackBar calls
    final pattern = RegExp(r'\bshowOverlaySnackBar\s*\(');

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
        // allow internal helper file that defines _showOverlaySnackBar
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
      reason: 'Found direct showOverlaySnackBar usages in files: ${badFiles.join(', ')}. Use showAppSnackBar instead.',
    );
  });
}
