import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No direct showDialog usages in lib (use showAppDialog)', () {
    final dir = Directory('lib');
    final badFiles = <String>[];
    final pattern = RegExp(r"\bshowDialog(?:\s*<[^>]*>)?\s*\(");

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final parts = entity.path.split(Platform.pathSeparator);
        final libIndex = parts.indexOf('lib');
        String rel;
        if (libIndex != -1) {
          rel = parts.sublist(libIndex).join('/');
        } else {
          rel = entity.path.replaceAll(Platform.pathSeparator, '/');
        }
        if (rel == 'lib/shared/utils/dialog_utils.dart') continue;
        final content = entity.readAsStringSync();
        if (pattern.hasMatch(content)) badFiles.add(rel);
      }
    }

    expect(badFiles, isEmpty, reason: 'Found direct showDialog usages in files: ${badFiles.join(', ')}');
  });

  test('No direct showSnackBar or showOverlaySnackBar usages in lib (use showAppSnackBar)', () {
    final dir = Directory('lib');
    final badFilesSnack = <String>[];
    final patternSnack = RegExp(r'(\.showSnackBar\s*\(|\bshowSnackBar\s*\()');
    final badFilesOverlay = <String>[];
    final patternOverlay = RegExp(r'\bshowOverlaySnackBar\s*\(');

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final parts = entity.path.split(Platform.pathSeparator);
        final libIndex = parts.indexOf('lib');
        String rel;
        if (libIndex != -1) {
          rel = parts.sublist(libIndex).join('/');
        } else {
          rel = entity.path.replaceAll(Platform.pathSeparator, '/');
        }
        if (rel == 'lib/shared/utils/dialog_utils.dart') continue;

        final content = entity.readAsStringSync();
        if (patternSnack.hasMatch(content)) badFilesSnack.add(rel);
        if (patternOverlay.hasMatch(content)) badFilesOverlay.add(rel);
      }
    }

    expect(badFilesSnack, isEmpty, reason: 'Found direct showSnackBar usages in files: ${badFilesSnack.join(', ')}');
    expect(
      badFilesOverlay,
      isEmpty,
      reason:
          'Found direct showOverlaySnackBar usages in files: ${badFilesOverlay.join(', ')}. Use showAppSnackBar instead.',
    );
  });
}
