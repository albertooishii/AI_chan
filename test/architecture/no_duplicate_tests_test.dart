import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';

/// Test que falla si hay archivos de test duplicados o muy parecidos.
///
/// Reglas:
/// - Escanea `test/` recursivamente.
/// - Ignora `test/fakes/` y `test/disabled/`.
/// - Detecta duplicados exactos por hash MD5.
/// - Detecta archivos con alta similitud (ratio >= 0.80) usando una comparación
///   basada en SequenceMatcher simplificada (ratio de texto normalizado).
///
/// Umbrales actuales:
/// - similitud principal (heurística híbrida): >= 0.40
/// - shingles (Jaccard): >= 0.40 (k=5)
/// - solapamiento de nombres de `test(...)`: >= 0.40
void main() {
  test('No duplicate or highly-similar test files', () {
    final base = Directory('test');
    if (!base.existsSync()) return;

    // Recolectar archivos relevantes
    final files = <File>[];
    for (final ent in base.listSync(recursive: true)) {
      if (ent is! File) continue;
      final path = ent.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      if (path.contains('test/fakes/') || path.contains('test/disabled/')) continue;
      files.add(ent);
    }

    // Normalizar contenido: quitar imports, comentarios de línea y bloques, y espacio extra
    String normalize(String s) {
      final lines = <String>[];
      var inBlock = false;
      for (final raw in LineSplitter.split(s)) {
        var line = raw.trim();
        if (inBlock) {
          if (line.contains('*/')) {
            inBlock = false;
            // remove up to end of block
            final idx = line.indexOf('*/');
            line = line.substring(idx + 2).trim();
            if (line.isEmpty) continue;
          } else {
            continue;
          }
        }
        if (line.startsWith('/*')) {
          inBlock = true;
          if (line.contains('*/')) {
            inBlock = false;
            final after = line.substring(line.indexOf('*/') + 2).trim();
            if (after.isEmpty) continue;
            line = after;
          } else {
            continue;
          }
        }
        if (line.startsWith('//')) continue;
        if (line.startsWith('import ') || line.startsWith('part ') || line.startsWith('library ')) continue;
        if (line.isEmpty) continue;
        lines.add(line);
      }
      return lines.join('\n');
    }

    // Hash para duplicados exactos
    final hashToFiles = <String, List<String>>{};
    final normCache = <String, String>{};
    for (final f in files) {
      final txt = f.readAsStringSync();
      final norm = normalize(txt);
      normCache[f.path] = norm;
      final h = md5.convert(utf8.encode(norm)).toString();
      hashToFiles.putIfAbsent(h, () => []).add(f.path.replaceAll('\\', '/'));
    }

    // Buscar duplicados exactos
    final exactDups = hashToFiles.values.where((l) => l.length > 1).toList();

    // Comparar similitud por pares (ratio simple)
    double similarity(String a, String b) {
      // Implementación simple de ratio basada en LCS vía SequenceMatcher-like
      // Para evitar dependencias externas, usamos un algoritmo ingenuo:
      final la = a.length, lb = b.length;
      if (la == 0 && lb == 0) {
        return 1.0;
      }
      if (la == 0 || lb == 0) {
        return 0.0;
      }
      // Longest common subsequence length approximation via common prefix/suffix trimmed
      final minLen = (la < lb) ? la : lb;
      var common = 0;
      for (var i = 0; i < minLen; i++) {
        if (a[i] == b[i]) {
          common++;
        } else {
          break;
        }
      }
      // fallback: use shared token count
      final sa = a.split(RegExp(r'\W+')).where((s) => s.isNotEmpty).toSet();
      final sb = b.split(RegExp(r'\W+')).where((s) => s.isNotEmpty).toSet();
      final inter = sa.intersection(sb).length;
      final union = sa.union(sb).length;
      final tokenRatio = union == 0 ? 0.0 : inter / union;
      // combine both heuristics
      return 0.4 * (common / minLen) + 0.6 * tokenRatio;
    }

    // Additional similarity heuristics
    List<String> shingles(String s, int k) {
      final tokens = s.split(RegExp(r'\W+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length < k) return <String>[];
      final set = <String>{};
      for (var i = 0; i <= tokens.length - k; i++) {
        set.add(tokens.sublist(i, i + k).join(' '));
      }
      return set.toList();
    }

    double jaccard(Iterable a, Iterable b) {
      final sa = a.toSet();
      final sb = b.toSet();
      final inter = sa.intersection(sb).length;
      final union = sa.union(sb).length;
      if (union == 0) return 0.0;
      return inter / union;
    }

    List<String> extractTestNames(String s) {
      final reg = RegExp(r'''test\s*\(\s*['\"](.*?)['\"]''', multiLine: true);
      return reg.allMatches(s).map((m) => (m.group(1) ?? '').trim()).where((t) => t.isNotEmpty).toList();
    }

    final similarPairs = <Map<String, dynamic>>[];
    final paths = files.map((f) => f.path.replaceAll('\\', '/')).toList();
    const shingleK = 5;
    const shingleThreshold = 0.40; // Jaccard threshold for shingles
    const nameOverlapThreshold = 0.40; // overlap for test() names
    for (var i = 0; i < paths.length; i++) {
      for (var j = i + 1; j < paths.length; j++) {
        final a = normCache[paths[i]] ?? '';
        final b = normCache[paths[j]] ?? '';
        final r = similarity(a, b);
        // shingle Jaccard
        final shA = shingles(a, shingleK);
        final shB = shingles(b, shingleK);
        final shJ = jaccard(shA, shB);
        // test name overlap
        final na = extractTestNames(a).toSet();
        final nb = extractTestNames(b).toSet();
        final nameOverlap = (na.union(nb).isEmpty) ? 0.0 : (na.intersection(nb).length / na.union(nb).length);

        // decide if any heuristic flags this pair (umbral principal 0.40)
        if (r >= 0.40 || shJ >= shingleThreshold || nameOverlap >= nameOverlapThreshold) {
          similarPairs.add({'a': paths[i], 'b': paths[j], 'r': r, 'shJ': shJ, 'nameOverlap': nameOverlap});
        }
      }
    }

    if (exactDups.isEmpty && similarPairs.isEmpty) {
      return;
    }

    final sb = StringBuffer();
    sb.writeln('Se encontraron duplicados o tests muy similares:');

    if (exactDups.isNotEmpty) {
      sb.writeln('\nDuplicados exactos (mismo contenido normalizado):');
      for (final group in exactDups) {
        for (final p in group) {
          sb.writeln('  - $p');
        }
        sb.writeln('');
      }
      sb.writeln('Puedes conservar uno por grupo y eliminar el resto. Ejemplos de comandos:');
      for (final group in exactDups) {
        // keep first, suggest rm for others
        final keep = group.first;
        for (final p in group.skip(1)) {
          sb.writeln("  rm -v '$p'");
          sb.writeln("  git rm -v '$p' && git commit -m 'chore(tests): remove duplicated test $p'");
        }
        sb.writeln('  # conservar: $keep\n');
      }
    }

    if (similarPairs.isNotEmpty) {
      sb.writeln('\nTests con alta similitud (ratio >= 0.40 o heurísticas adicionales):');
      for (final m in similarPairs) {
        sb.writeln('  - (${(m['r'] as double).toStringAsFixed(2)}) ${m['a']} <-> ${m['b']}');
        sb.writeln('    Revisa si ambos son necesarios; si no, elimina uno:');
        sb.writeln("    rm -v '${m['b']}'");
        sb.writeln("    git rm -v '${m['b']}' && git commit -m 'chore(tests): remove similar test ${m['b']}'");
      }
    }

    fail(sb.toString());
  });
}
