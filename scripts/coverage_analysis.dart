#!/usr/bin/env dart

library;

/// 📊 Análisis Automático de Cobertura de Tests
///
/// Este script analiza el archivo lcov.info para identificar:
/// 1. 🚨 Archivos críticos con 0% cobertura
/// 2. 📈 Oportunidades de mejora (baja cobertura)
/// 3. 🎯 Prioridades por complejidad y criticidad
/// 4. 📋 Recomendaciones específicas

import 'dart:io';

Future<void> main() async {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    stderr.writeln('❌ Archivo coverage/lcov.info no encontrado.');
    stderr.writeln('   Ejecuta: flutter test --coverage');
    exit(1);
  }

  final content = await lcovFile.readAsString();
  final report = analyzeCoverage(content);

  final output = generateReport(report);
  stdout.write(output);
}

class CoverageData {

  CoverageData({
    required this.filePath,
    required this.totalLines,
    required this.coveredLines,
    required this.coveragePercent,
    required this.priority,
  });
  final String filePath;
  final int totalLines;
  final int coveredLines;
  final double coveragePercent;
  final Priority priority;
}

enum Priority { critical, high, medium, low }

class CoverageReport {

  CoverageReport({
    required this.files,
    required this.overallCoverage,
    required this.totalLines,
    required this.totalCoveredLines,
  });
  final List<CoverageData> files;
  final double overallCoverage;
  final int totalLines;
  final int totalCoveredLines;
}

CoverageReport analyzeCoverage(final String lcovContent) {
  final files = <CoverageData>[];
  final lines = lcovContent.split('\n');

  String? currentFile;
  int? linesFound;
  int? linesHit;

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
    } else if (line.startsWith('LF:')) {
      linesFound = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      linesHit = int.parse(line.substring(3));
    } else if (line == 'end_of_record' && currentFile != null) {
      if (linesFound != null && linesHit != null) {
        final coverage = linesFound > 0 ? (linesHit / linesFound) * 100 : 0.0;
        final priority = calculatePriority(currentFile, coverage, linesFound);

        files.add(
          CoverageData(
            filePath: currentFile,
            totalLines: linesFound,
            coveredLines: linesHit,
            coveragePercent: coverage,
            priority: priority,
          ),
        );
      }

      currentFile = null;
      linesFound = null;
      linesHit = null;
    }
  }

  final totalLines = files.fold(0, (final sum, final file) => sum + file.totalLines);
  final totalCovered = files.fold(0, (final sum, final file) => sum + file.coveredLines);
  final overallCoverage = totalLines > 0 ? (totalCovered / totalLines) * 100 : 0.0;

  return CoverageReport(
    files: files,
    overallCoverage: overallCoverage,
    totalLines: totalLines,
    totalCoveredLines: totalCovered,
  );
}

Priority calculatePriority(final String filePath, final double coverage, final int lines) {
  // Factor 1: Tipo de archivo (criticidad del dominio)
  int criticalityScore = 0;

  if (filePath.contains('/use_cases/') || filePath.contains('/services/') || filePath.contains('/domain/')) {
    criticalityScore += 3; // Lógica de negocio crítica
  } else if (filePath.contains('/controllers/') || filePath.contains('/repositories/')) {
    criticalityScore += 2; // Lógica de aplicación importante
  } else if (filePath.contains('/adapters/') || filePath.contains('/infrastructure/')) {
    criticalityScore += 1; // Infraestructura
  }

  // Factor 2: Complejidad (más líneas = más complejo)
  if (lines > 200) {
    criticalityScore += 2;
  } else if (lines > 100) {
    criticalityScore += 1;
  }

  // Factor 3: Cobertura actual
  if (coverage == 0) {
    criticalityScore += 3;
  } else if (coverage < 20) {
    criticalityScore += 2;
  } else if (coverage < 50) {
    criticalityScore += 1;
  }

  // Determinar prioridad final
  if (criticalityScore >= 7) return Priority.critical;
  if (criticalityScore >= 5) return Priority.high;
  if (criticalityScore >= 3) return Priority.medium;
  return Priority.low;
}

void _appendCategoryStats(final StringBuffer output, final List<CoverageData> files, final String category, final String pathPattern) {
  final categoryFiles = files.where((final f) => f.filePath.contains(pathPattern)).toList();
  if (categoryFiles.isEmpty) return;

  final totalLines = categoryFiles.fold(0, (final sum, final f) => sum + f.totalLines);
  final coveredLines = categoryFiles.fold(0, (final sum, final f) => sum + f.coveredLines);
  final avgCoverage = totalLines > 0 ? (coveredLines / totalLines) * 100 : 0.0;
  final zeroCoverage = categoryFiles.where((final f) => f.coveragePercent == 0).length;

  output.writeln(
    '$category: ${avgCoverage.toStringAsFixed(1)}% (${categoryFiles.length} archivos, $zeroCoverage sin cobertura)',
  );
}

String generateReport(final CoverageReport report) {
  final output = StringBuffer();

  output.writeln('🔍 ANÁLISIS AUTOMÁTICO DE COBERTURA DE TESTS');
  output.writeln('============================================\n');

  // Análisis general
  output.writeln('📊 RESUMEN GENERAL');
  output.writeln('─────────────────');
  output.writeln('Cobertura global: ${report.overallCoverage.toStringAsFixed(1)}%');
  output.writeln('Líneas cubiertas: ${report.totalCoveredLines}/${report.totalLines}');
  output.writeln('Archivos analizados: ${report.files.length}');
  output.writeln();

  // Agrupar por prioridad
  final critical = report.files.where((final f) => f.priority == Priority.critical).toList();
  final high = report.files.where((final f) => f.priority == Priority.high).toList();
  final medium = report.files.where((final f) => f.priority == Priority.medium).toList();

  // Ordenar por cobertura (menor primero)
  critical.sort((final a, final b) => a.coveragePercent.compareTo(b.coveragePercent));
  high.sort((final a, final b) => a.coveragePercent.compareTo(b.coveragePercent));
  medium.sort((final a, final b) => a.coveragePercent.compareTo(b.coveragePercent));

  if (critical.isNotEmpty) {
    output.writeln('🚨 PRIORIDAD CRÍTICA (${critical.length} archivos)');
    output.writeln('══════════════════════════════════════════');
    for (final file in critical.take(10)) {
      output.writeln('❌ ${_getFileName(file.filePath)}');
      output.writeln(
        '   Cobertura: ${file.coveragePercent.toStringAsFixed(1)}% (${file.coveredLines}/${file.totalLines} líneas)',
      );
      output.writeln('   📁 ${file.filePath}');
      output.writeln();
    }
  }

  if (high.isNotEmpty) {
    output.writeln('⚠️  PRIORIDAD ALTA (${high.length} archivos)');
    output.writeln('════════════════════════════════════════');
    for (final file in high.take(8)) {
      output.writeln('📊 ${_getFileName(file.filePath)}');
      output.writeln(
        '   Cobertura: ${file.coveragePercent.toStringAsFixed(1)}% (${file.coveredLines}/${file.totalLines} líneas)',
      );
      output.writeln('   📁 ${file.filePath}');
      output.writeln();
    }
  }

  if (medium.isNotEmpty) {
    output.writeln('📈 PRIORIDAD MEDIA (${medium.length} archivos)');
    output.writeln('═══════════════════════════════════════════');
    output.writeln('Los primeros 5 archivos con menor cobertura:');
    for (final file in medium.take(5)) {
      output.writeln('• ${_getFileName(file.filePath)}: ${file.coveragePercent.toStringAsFixed(1)}%');
    }
    output.writeln();
  }

  // Estadísticas por categoría
  output.writeln('📋 ESTADÍSTICAS POR CATEGORÍA');
  output.writeln('═════════════════════════════');
  _appendCategoryStats(output, report.files, 'Use Cases', '/use_cases/');
  _appendCategoryStats(output, report.files, 'Services', '/services/');
  _appendCategoryStats(output, report.files, 'Controllers', '/controllers/');
  _appendCategoryStats(output, report.files, 'Domain', '/domain/');
  _appendCategoryStats(output, report.files, 'Infrastructure', '/infrastructure/');
  _appendCategoryStats(output, report.files, 'Presentation', '/presentation/');

  // Recomendaciones
  output.writeln('\n🎯 RECOMENDACIONES ESPECÍFICAS');
  output.writeln('═════════════════════════════');

  if (critical.isNotEmpty) {
    output.writeln('\n🔥 ACCIÓN INMEDIATA REQUERIDA:');
    output.writeln('──────────────────────────────');

    final useCases = critical.where((final f) => f.filePath.contains('/use_cases/')).toList();
    final services = critical.where((final f) => f.filePath.contains('/services/')).toList();
    final controllers = critical.where((final f) => f.filePath.contains('/controllers/')).toList();

    if (useCases.isNotEmpty) {
      output.writeln('\n1️⃣ USE CASES (lógica de negocio crítica):');
      for (final file in useCases.take(3)) {
        output.writeln('   • ${_getFileName(file.filePath)}');
        output.writeln('     → Crear ${_getTestFileName(file.filePath)}');
        output.writeln('     → Probar casos felices y de error');
      }
    }

    if (services.isNotEmpty) {
      output.writeln('\n2️⃣ SERVICES (servicios de aplicación):');
      for (final file in services.take(3)) {
        output.writeln('   • ${_getFileName(file.filePath)}');
        output.writeln('     → Crear ${_getTestFileName(file.filePath)}');
        output.writeln('     → Mock dependencies y validar comportamiento');
      }
    }

    if (controllers.isNotEmpty) {
      output.writeln('\n3️⃣ CONTROLLERS (coordinación de flujos):');
      for (final file in controllers.take(3)) {
        output.writeln('   • ${_getFileName(file.filePath)}');
        output.writeln('     → Crear ${_getTestFileName(file.filePath)}');
        output.writeln('     → Testear estados y navegación');
      }
    }
  }

  output.writeln('\n📝 PRÓXIMOS PASOS:');
  output.writeln('─────────────────');
  output.writeln('1. Crear tests para archivos de prioridad CRÍTICA');
  output.writeln('2. Alcanzar mínimo 70% cobertura en use cases');
  output.writeln('3. Implementar integration tests para flujos principales');
  output.writeln('4. Configurar coverage gates en CI/CD');
  output.writeln();
  output.writeln(
    '💡 TIP: Ejecutar `flutter test --coverage && dart scripts/coverage_analysis.dart` después de agregar tests',
  );

  return output.toString();
}

Future<void> generateRecommendations(final CoverageReport report) async {
  // Esta función ya no es necesaria, todo se maneja en generateReport
}

String _getFileName(final String path) {
  return path.split('/').last;
}

String _getTestFileName(final String path) {
  final fileName = _getFileName(path);
  return fileName.replaceAll('.dart', '_test.dart');
}
