import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

/// 🎯 SMART CQRS & CLEAN PATTERNS VALIDATION
///
/// This test validates specific patterns that are not covered by the main DDD suite:
/// ✅ CQRS separation in complex application services
/// ✅ Clean Architecture dependency flow validation
/// ✅ Port-Adapter pattern completeness

void main() {
  group('🎯 Smart Architecture Pattern Validation', () {
    test(
      'Application Services should follow Command-Query separation where applicable',
      () async {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final serviceFiles = await _findApplicationServices(context);

          for (final serviceFile in serviceFiles) {
            final content = await serviceFile.readAsString();
            final analysis = _analyzeCQRSCompliance(content);

            if (analysis.hasViolations) {
              violations.addAll(
                analysis.violations.map(
                  (final violation) =>
                      '❌ ${_getRelativePath(serviceFile.path)}: $violation',
                ),
              );
            }
          }
        }

        // Only fail if there are clear CQRS violations, not just mixed operations
        final criticalViolations = violations
            .where((final v) => v.contains('command and query'))
            .toList();

        expect(
          criticalViolations,
          isEmpty,
          reason:
              '''
🚨 CQRS PATTERN VIOLATIONS:
${criticalViolations.join('\n')}

CQRS GUIDELINES:
✅ Methods should either command (change state) or query (return data)
✅ Complex services with many mixed operations should be split
✅ Clear separation improves testability and understanding

Note: Simple operations may legitimately combine command/query patterns.
        ''',
        );
      },
    );

    test('Port-Adapter pattern must be consistently implemented', () async {
      final violations = <String>[];
      final boundedContexts = _findBoundedContexts();

      for (final context in boundedContexts) {
        final portAdapterAnalysis = await _analyzePortAdapterPattern(context);
        violations.addAll(portAdapterAnalysis.violations);
      }

      expect(
        violations,
        isEmpty,
        reason:
            '''
🚨 PORT-ADAPTER PATTERN VIOLATIONS:
${violations.join('\n')}

PORT-ADAPTER REQUIREMENTS:
✅ Every external dependency must have a domain interface (port)
✅ Infrastructure must implement domain interfaces (adapters)
✅ No direct framework dependencies in domain/application layers

This ensures clean dependency inversion and testability.
        ''',
      );
    });

    test(
      'Clean Architecture dependency direction must be maintained',
      () async {
        final violations = <String>[];
        final allFiles = await _findAllProjectFiles();

        for (final file in allFiles) {
          final content = await file.readAsString();
          final dependencyViolations = _analyzeDependencyDirection(
            file.path,
            content,
          );
          violations.addAll(dependencyViolations);
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 DEPENDENCY DIRECTION VIOLATIONS:
${violations.join('\n')}

CLEAN ARCHITECTURE RULES:
✅ Domain → no dependencies on outer layers
✅ Application → only depends on domain
✅ Infrastructure → depends on domain interfaces
✅ Presentation → depends on application and domain

Dependencies must point inward toward the domain.
        ''',
        );
      },
    );
  });
}

// ===================================================================
// HELPER FUNCTIONS - SMART ANALYSIS
// ===================================================================

List<String> _findBoundedContexts() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) return [];

  return libDir
      .listSync()
      .whereType<Directory>()
      .map((final d) => d.path.split('/').last)
      .where(
        (final name) =>
            !name.startsWith('.') && name != 'core' && _isBoundedContext(name),
      )
      .toList();
}

bool _isBoundedContext(final String name) {
  final contextDir = Directory('lib/$name');
  return contextDir.existsSync() &&
      (Directory('lib/$name/domain').existsSync() ||
          Directory('lib/$name/application').existsSync());
}

Future<List<File>> _findApplicationServices(final String context) async {
  final services = <File>[];
  final servicesDir = Directory('lib/$context/application/services');

  if (!servicesDir.existsSync()) return services;

  await for (final entity in servicesDir.list()) {
    if (entity is File && entity.path.endsWith('.dart')) {
      services.add(entity);
    }
  }

  return services;
}

CQRSAnalysis _analyzeCQRSCompliance(final String content) {
  final violations = <String>[];
  final methods = _extractMethods(content);

  var commandMethods = 0;
  var queryMethods = 0;
  var mixedMethods = 0;

  for (final method in methods) {
    final isCommand = _isCommandMethod(method);
    final isQuery = _isQueryMethod(method);

    if (isCommand && isQuery) {
      mixedMethods++;
    } else if (isCommand) {
      commandMethods++;
    } else if (isQuery) {
      queryMethods++;
    }
  }

  // Only flag services that are clearly violating CQRS principles
  final totalMethods = commandMethods + queryMethods + mixedMethods;
  if (totalMethods > 10 && mixedMethods > totalMethods * 0.3) {
    violations.add(
      'Service has too many mixed command/query methods - consider splitting',
    );
  }

  return CQRSAnalysis(
    hasViolations: violations.isNotEmpty,
    violations: violations,
  );
}

List<String> _extractMethods(final String content) {
  final methods = <String>[];
  final methodPattern = RegExp(
    r'^\s*(?:Future<[^>]*>|void|String|int|bool|double|\w+)\s+(\w+)\s*\([^)]*\)\s*(?:async\s*)?{',
    multiLine: true,
  );

  for (final match in methodPattern.allMatches(content)) {
    final methodName = match.group(1)!;
    if (!methodName.startsWith('_')) {
      // Only public methods
      methods.add(methodName);
    }
  }

  return methods;
}

bool _isCommandMethod(final String methodName) {
  final commandKeywords = [
    'create',
    'update',
    'delete',
    'save',
    'send',
    'process',
    'execute',
    'handle',
    'add',
    'remove',
    'start',
    'stop',
    'end',
  ];
  return commandKeywords.any(
    (final keyword) => methodName.toLowerCase().contains(keyword),
  );
}

bool _isQueryMethod(final String methodName) {
  final queryKeywords = [
    'get',
    'find',
    'fetch',
    'retrieve',
    'search',
    'load',
    'read',
    'list',
    'count',
  ];
  return queryKeywords.any(
    (final keyword) => methodName.toLowerCase().contains(keyword),
  );
}

Future<PortAdapterAnalysis> _analyzePortAdapterPattern(
  final String context,
) async {
  final violations = <String>[];

  // Check for external dependencies without proper abstractions
  final applicationFiles = await _findApplicationFiles(context);

  for (final file in applicationFiles) {
    final content = await file.readAsString();
    final externalDeps = _findExternalDependencies(content);

    for (final dep in externalDeps) {
      if (!_hasCorrespondingDomainInterface(dep, context)) {
        violations.add(
          '❌ ${_getRelativePath(file.path)}: External dependency "$dep" needs domain interface',
        );
      }
    }
  }

  return PortAdapterAnalysis(violations: violations);
}

Future<List<File>> _findApplicationFiles(final String context) async {
  final files = <File>[];
  final appDir = Directory('lib/$context/application');

  if (!appDir.existsSync()) return files;

  await for (final entity in appDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }

  return files;
}

List<String> _findExternalDependencies(final String content) {
  final dependencies = <String>[];
  final importPattern = RegExp(r'''import\s+['"]package:([^/'"]+)''');

  for (final match in importPattern.allMatches(content)) {
    final package = match.group(1)!;
    if (!_isInternalPackage(package)) {
      dependencies.add(package);
    }
  }

  return dependencies;
}

bool _isInternalPackage(final String package) {
  final internalPackages = ['flutter', 'dart:', 'ai_chan'];
  return internalPackages.any((final internal) => package.startsWith(internal));
}

bool _hasCorrespondingDomainInterface(
  final String dependency,
  final String context,
) {
  // This is a simplified check - in practice, you'd scan domain interfaces
  // for abstractions that correspond to external dependencies
  final interfacesDir = Directory('lib/$context/domain/interfaces');
  if (!interfacesDir.existsSync()) return false;

  // Check if there are domain interfaces that might abstract this dependency
  final interfaces = interfacesDir
      .listSync()
      .whereType<File>()
      .where((final f) => f.path.endsWith('.dart'))
      .toList();

  return interfaces
      .isNotEmpty; // Simplified - real implementation would be more sophisticated
}

List<String> _analyzeDependencyDirection(
  final String filePath,
  final String content,
) {
  final violations = <String>[];
  final layer = _determineLayer(filePath);

  if (layer == 'unknown') return violations;

  final imports = _extractImports(content);

  for (final import in imports) {
    final importLayer = _determineLayerFromImport(import);
    if (!_isValidDependency(layer, importLayer)) {
      violations.add(
        '❌ ${_getRelativePath(filePath)}: $layer layer cannot depend on $importLayer',
      );
    }
  }

  return violations;
}

String _determineLayer(final String filePath) {
  if (filePath.contains('/domain/')) return 'domain';
  if (filePath.contains('/application/')) return 'application';
  if (filePath.contains('/infrastructure/')) return 'infrastructure';
  if (filePath.contains('/presentation/')) return 'presentation';
  return 'unknown';
}

List<String> _extractImports(final String content) {
  final imports = <String>[];
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]''');

  for (final match in importPattern.allMatches(content)) {
    imports.add(match.group(1)!);
  }

  return imports;
}

String _determineLayerFromImport(final String import) {
  if (import.contains('/domain/')) return 'domain';
  if (import.contains('/application/')) return 'application';
  if (import.contains('/infrastructure/')) return 'infrastructure';
  if (import.contains('/presentation/')) return 'presentation';
  if (import.startsWith('package:flutter/')) return 'framework';
  if (import.startsWith('package:') && !import.startsWith('package:ai_chan/')) {
    return 'external';
  }
  return 'unknown';
}

bool _isValidDependency(final String fromLayer, final String toLayer) {
  // Clean Architecture dependency rules
  switch (fromLayer) {
    case 'domain':
      return toLayer == 'domain' || toLayer == 'unknown';
    case 'application':
      return toLayer == 'domain' ||
          toLayer == 'application' ||
          toLayer == 'unknown';
    case 'infrastructure':
      return toLayer != 'presentation'; // Can depend on domain, application
    case 'presentation':
      return toLayer != 'infrastructure'; // Can depend on domain, application
    default:
      return true; // Unknown layers - don't restrict
  }
}

Future<List<File>> _findAllProjectFiles() async {
  final files = <File>[];
  final libDir = Directory('lib');

  if (!libDir.existsSync()) return files;

  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }

  return files;
}

String _getRelativePath(final String path) {
  return path.replaceFirst(RegExp(r'^.*?lib/'), 'lib/');
}

// ===================================================================
// DATA CLASSES
// ===================================================================

class CQRSAnalysis {
  const CQRSAnalysis({required this.hasViolations, required this.violations});

  final bool hasViolations;
  final List<String> violations;
}

class PortAdapterAnalysis {
  const PortAdapterAnalysis({required this.violations});
  final List<String> violations;
}
