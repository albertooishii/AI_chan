import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// 🏗️ ROBUST DDD HEXAGONAL ARCHITECTURE VALIDATION SUITE
///
/// This test suite ensures:
/// ✅ Uniform DDD structure across all bounded contexts
/// ✅ Proper hexagonal architecture implementation
/// ✅ Clean domain-driven design principles
/// ✅ Robust isolation and separation of concerns
/// ✅ Intelligent analysis that focuses on real architectural issues

void main() {
  group('🏗️ DDD Hexagonal Architecture - Robust Validation Suite', () {
    // ===================================================================
    // 1. BOUNDED CONTEXT STRUCTURE UNIFORMITY
    // ===================================================================
    group('📐 Bounded Context Structure Uniformity', () {
      test('All bounded contexts must have uniform DDD structure', () async {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        if (boundedContexts.isEmpty) {
          fail('No bounded contexts found in project');
        }

        for (final context in boundedContexts) {
          final analysis = await _analyzeBoundedContextStructure(context);
          violations.addAll(analysis.violations);
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 BOUNDED CONTEXT STRUCTURE VIOLATIONS:
${violations.join('\n')}

REQUIRED DDD STRUCTURE FOR EACH BOUNDED CONTEXT:
✅ domain/interfaces/ (ports)
✅ domain/models/ or domain/entities/
✅ application/services/ (coordinators)
✅ application/use_cases/ (business operations)
✅ infrastructure/adapters/ (implementations)
✅ presentation/ (UI layer)

EACH LAYER MUST HAVE CLEAR RESPONSIBILITY AND PROPER ISOLATION
          ''',
        );
      });

      test(
        'Bounded contexts must have consistent quality and completeness',
        () async {
          final violations = <String>[];
          final boundedContexts = _findBoundedContexts();
          final qualityScores = <String, int>{};

          for (final context in boundedContexts) {
            final score = await _calculateContextQualityScore(context);
            qualityScores[context] = score;
          }

          final average = qualityScores.values.isNotEmpty
              ? (qualityScores.values.reduce((final a, final b) => a + b) /
                        qualityScores.values.length)
                    .round()
              : 0;

          // Flag contexts that are significantly below average
          for (final entry in qualityScores.entries) {
            if (entry.value < average - 25 || entry.value < 60) {
              violations.add(
                '❌ ${entry.key} context quality too low: ${entry.value}/100 (avg: $average)',
              );
            }
          }

          if (violations.isNotEmpty) {
            debugPrint('\n📊 BOUNDED CONTEXT QUALITY SCORES:');
            for (final entry in qualityScores.entries) {
              final status = entry.value >= average ? '✅' : '❌';
              debugPrint('$status ${entry.key}: ${entry.value}/100');
            }
          }

          expect(
            violations,
            isEmpty,
            reason:
                '''
🚨 BOUNDED CONTEXT QUALITY INCONSISTENCIES:
${violations.join('\n')}

All bounded contexts should maintain similar quality standards.
Low-quality contexts indicate incomplete DDD implementation.
          ''',
          );
        },
      );
    });

    // ===================================================================
    // 2. HEXAGONAL ARCHITECTURE VALIDATION
    // ===================================================================
    group('🔯 Hexagonal Architecture Implementation', () {
      test(
        'Domain interfaces must have corresponding infrastructure implementations',
        () async {
          final violations = <String>[];
          final boundedContexts = _findBoundedContexts();

          for (final context in boundedContexts) {
            final domainInterfaces = await _findDomainInterfaces(context);
            final infrastructureImpls =
                await _findInfrastructureImplementations(context);

            // Check interface-implementation pairing
            for (final interface in domainInterfaces) {
              final hasImplementation = infrastructureImpls.any(
                (final impl) => _implementsInterface(impl, interface),
              );

              if (!hasImplementation) {
                violations.add(
                  '❌ Missing implementation for ${interface.name} in $context context',
                );
              }
            }

            // Check for orphaned implementations (implementations without interfaces)
            for (final impl in infrastructureImpls) {
              final implementedInterfaces = _getImplementedInterfaces(
                impl.content,
              );
              final hasMatchingInterface = implementedInterfaces.any(
                (final interfaceName) => domainInterfaces.any(
                  (final di) => di.name == interfaceName,
                ),
              );

              if (!hasMatchingInterface && _shouldHaveInterface(impl)) {
                violations.add(
                  '⚠️ Orphaned implementation ${impl.className} in $context - consider creating domain interface',
                );
              }
            }
          }

          expect(
            violations,
            isEmpty,
            reason:
                '''
🚨 HEXAGONAL ARCHITECTURE VIOLATIONS:
${violations.join('\n')}

HEXAGONAL ARCHITECTURE REQUIRES:
✅ Every domain interface (port) has infrastructure implementation (adapter)
✅ Infrastructure implementations should implement domain interfaces
✅ No orphaned implementations without corresponding domain contracts

This ensures proper dependency inversion and testability.
          ''',
          );
        },
      );

      test(
        'Domain layer must only depend on abstractions, never implementations',
        () async {
          final violations = <String>[];
          final boundedContexts = _findBoundedContexts();

          for (final context in boundedContexts) {
            final domainFiles = await _findDomainFiles(context);

            for (final file in domainFiles) {
              final content = await file.readAsString();
              final invalidDependencies = _findInvalidDomainDependencies(
                content,
                context,
              );

              for (final dependency in invalidDependencies) {
                violations.add(
                  '❌ ${_getRelativePath(file.path)}: Invalid dependency on $dependency',
                );
              }
            }
          }

          expect(
            violations,
            isEmpty,
            reason:
                '''
🚨 DOMAIN LAYER DEPENDENCY VIOLATIONS:
${violations.join('\n')}

DOMAIN LAYER RULES:
✅ Can only import from same bounded context domain
✅ Can import from shared/core domain abstractions
✅ CANNOT import from infrastructure or presentation layers
✅ CANNOT import from other bounded contexts
✅ CANNOT import concrete implementations

Domain must remain pure and dependency-free.
          ''',
          );
        },
      );
    });

    // ===================================================================
    // 3. BOUNDED CONTEXT ISOLATION
    // ===================================================================
    group('🔒 Bounded Context Isolation', () {
      test('Bounded contexts must be properly isolated', () async {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final isolationViolations = await _checkBoundedContextIsolation(
            context,
            boundedContexts,
          );
          violations.addAll(isolationViolations);
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 BOUNDED CONTEXT ISOLATION VIOLATIONS:
${violations.join('\n')}

ISOLATION RULES:
✅ Domain layers cannot import from other bounded contexts
✅ Application layers should only import from shared/core
✅ Cross-context communication must go through well-defined interfaces
✅ No direct object instantiation across contexts

Proper isolation ensures contexts can evolve independently.
          ''',
        );
      });
    });

    // ===================================================================
    // 4. INTELLIGENT SINGLE RESPONSIBILITY ANALYSIS
    // ===================================================================
    group('🎯 Single Responsibility Principle', () {
      test('Application Services must have clear, single responsibility', () async {
        final violations = <String>[];
        final warnings = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final appServices = await _findApplicationServices(context);

          for (final service in appServices) {
            final analysis = await _analyzeServiceResponsibility(service);

            // Hard violations (fail the test)
            if (analysis.hasMultipleResponsibilities) {
              violations.add(
                '❌ ${_getRelativePath(service.path)}: Multiple responsibilities: ${analysis.responsibilities.join(', ')}',
              );
            }

            if (analysis.methodCount > 20) {
              violations.add(
                '❌ ${_getRelativePath(service.path)}: Too many methods (${analysis.methodCount}) - split into focused services',
              );
            }

            // Soft warnings (informational only)
            if (analysis.lineCount > 800) {
              warnings.add(
                '📏 ${_getRelativePath(service.path)}: Large service (${analysis.lineCount} lines) - consider splitting',
              );
            }
          }
        }

        // Show warnings as information
        if (warnings.isNotEmpty) {
          debugPrint('\n📊 SERVICE SIZE ANALYSIS (informational):');
          for (final warning in warnings) {
            debugPrint(warning);
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 SINGLE RESPONSIBILITY VIOLATIONS:
${violations.join('\n')}

APPLICATION SERVICES SHOULD:
✅ Have single, clear responsibility
✅ Coordinate use cases, not implement business logic
✅ Have reasonable method count (<20)
✅ Focus on one specific domain area

Services with multiple responsibilities should be split into focused services.
          ''',
        );
      });

      test('Use Cases must be focused and atomic', () async {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final useCases = await _findUseCases(context);

          for (final useCase in useCases) {
            final analysis = await _analyzeUseCaseDesign(useCase);

            if (analysis.isTooBroad) {
              violations.add(
                '❌ ${_getRelativePath(useCase.path)}: Use case is too broad - should be more focused',
              );
            }

            if (analysis.hasInfrastructureDependencies) {
              violations.add(
                '❌ ${_getRelativePath(useCase.path)}: Use case depends on infrastructure - use domain interfaces',
              );
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 USE CASE DESIGN VIOLATIONS:
${violations.join('\n')}

USE CASES SHOULD:
✅ Represent single business operation
✅ Be atomic and focused
✅ Only depend on domain interfaces
✅ Have clear input/output contracts

Broad use cases should be split into smaller, focused operations.
          ''',
        );
      });
    });

    // ===================================================================
    // 5. INTELLIGENT FILE PLACEMENT & NAMING
    // ===================================================================
    group('📁 File Placement & Naming Conventions', () {
      test(
        'Files must be placed in correct layers according to their purpose',
        () async {
          final violations = <String>[];
          final allFiles = await _findAllProjectFiles();

          for (final filePath in allFiles) {
            final content = await File(filePath).readAsString();
            final expectedLayer = _determineExpectedLayer(filePath, content);
            final actualLayer = _determineActualLayer(filePath);

            if (expectedLayer != actualLayer && expectedLayer != 'unknown') {
              violations.add(
                '❌ ${_getRelativePath(filePath)}: Should be in $expectedLayer layer, found in $actualLayer',
              );
            }
          }

          expect(
            violations,
            isEmpty,
            reason:
                '''
🚨 FILE PLACEMENT VIOLATIONS:
${violations.join('\n')}

FILE PLACEMENT RULES:
✅ Interfaces/abstractions → domain/interfaces/
✅ Business entities/models → domain/models/ or domain/entities/
✅ Domain services → domain/services/
✅ Use cases → application/use_cases/
✅ Application services → application/services/
✅ Controllers → application/controllers/
✅ Infrastructure implementations → infrastructure/adapters/
✅ UI components → presentation/

Each file must be in the layer that matches its actual responsibility.
          ''',
          );
        },
      );

      test('Naming conventions must be consistent and meaningful', () async {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final namingViolations = await _checkNamingConventions(context);
          violations.addAll(namingViolations);
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 NAMING CONVENTION VIOLATIONS:
${violations.join('\n')}

NAMING CONVENTIONS:
✅ Interfaces: I{Name} or {Name}Port (e.g., IChatRepository, ChatRepositoryPort)
✅ Application Services: {Context}ApplicationService
✅ Use Cases: {Action}{Entity}UseCase (e.g., SendMessageUseCase)
✅ Domain Services: {Name}DomainService
✅ Infrastructure Adapters: {Name}Adapter (e.g., SqlChatRepositoryAdapter)
✅ Controllers: {Name}Controller

Consistent naming improves code readability and understanding.
          ''',
        );
      });
    });

    // ===================================================================
    // 6. DRY PRINCIPLE VALIDATION
    // ===================================================================
    group('🔄 DRY Principle (Don\'t Repeat Yourself)', () {
      test('Code duplication must be minimal and justified', () async {
        final violations = <String>[];
        final allFiles = await _findAllProjectFiles();

        // Analyze code duplication across the project
        final duplicationAnalysis = await _analyzeDuplication(allFiles);

        for (final duplication in duplicationAnalysis.significantDuplications) {
          violations.add(
            '❌ Significant duplication detected: ${duplication.description}',
          );
        }

        // Show minor duplications as warnings
        if (duplicationAnalysis.minorDuplications.isNotEmpty) {
          debugPrint('\n📊 MINOR DUPLICATIONS (informational):');
          for (final minor in duplicationAnalysis.minorDuplications) {
            debugPrint('📝 ${minor.description}');
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 DRY PRINCIPLE VIOLATIONS:
${violations.join('\n')}

DRY REQUIREMENTS:
✅ Similar logic should be extracted to shared functions
✅ Repeated constants should be centralized
✅ Common patterns should use shared abstractions
✅ Domain logic duplication should be eliminated

Justified duplications: simple DTOs, different business contexts, performance-critical code.
          ''',
        );
      });

      test('Common patterns must be properly abstracted', () async {
        final violations = <String>[];
        final boundedContexts = _findBoundedContexts();

        for (final context in boundedContexts) {
          final patterns = await _analyzeCommonPatterns(context);

          for (final pattern in patterns.unabstractedPatterns) {
            violations.add(
              '❌ $context: Repeated pattern "${pattern.name}" should be abstracted (found ${pattern.occurrences} times)',
            );
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 PATTERN ABSTRACTION VIOLATIONS:
${violations.join('\n')}

COMMON PATTERNS THAT SHOULD BE ABSTRACTED:
✅ Repository implementations with similar CRUD operations
✅ Validation logic patterns
✅ Error handling patterns
✅ Mapping/transformation patterns
✅ Event handling patterns

Repeated patterns indicate opportunities for better abstractions.
          ''',
        );
      });

      test('Shared utilities must be used instead of duplicated code', () async {
        final violations = <String>[];
        final utilityAnalysis = await _analyzeUtilityUsage();

        for (final missed in utilityAnalysis.missedUtilizations) {
          violations.add(
            '❌ ${_getRelativePath(missed.filePath)}: Should use existing utility "${missed.utilityName}" instead of reimplementing',
          );
        }

        expect(
          violations,
          isEmpty,
          reason:
              '''
🚨 UTILITY USAGE VIOLATIONS:
${violations.join('\n')}

SHARED UTILITIES GUIDELINES:
✅ Use existing shared utilities instead of reimplementing
✅ Extract common utility functions to shared/utils/
✅ Avoid duplicating helper functions across contexts
✅ Centralize common transformations and validations

Check shared/utils/ before implementing common functionality.
          ''',
        );
      });
    });

    // ===================================================================
    // 7. CROSS-CUTTING CONCERNS VALIDATION
    // ===================================================================
    group('🌐 Cross-Cutting Concerns', () {
      test(
        'Shared context must only contain truly cross-cutting concerns',
        () async {
          final violations = <String>[];
          final sharedFiles = await _findSharedFiles();

          for (final file in sharedFiles) {
            final content = await file.readAsString();
            final isTrulyCrossCutting = _isAuenticlyCrossCuttingConcern(
              content,
              file.path,
            );

            if (!isTrulyCrossCutting) {
              violations.add(
                '❌ ${_getRelativePath(file.path)}: Not a cross-cutting concern - move to appropriate bounded context',
              );
            }
          }

          expect(
            violations,
            isEmpty,
            reason:
                '''
🚨 SHARED CONTEXT VIOLATIONS:
${violations.join('\n')}

SHARED/CORE SHOULD ONLY CONTAIN:
✅ Common value objects used by multiple contexts
✅ Cross-cutting technical concerns (logging, monitoring)
✅ Shared domain interfaces for integration
✅ Common utilities and constants
✅ Base classes and abstract implementations

Context-specific logic should be in the appropriate bounded context.
          ''',
          );
        },
      );
    });
  });
}

// ===================================================================
// HELPER FUNCTIONS - ROBUST ANALYSIS IMPLEMENTATIONS
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
            !name.startsWith('.') &&
            name != 'core' &&
            name != 'main.dart' &&
            _isBoundedContext(name),
      )
      .toList();
}

bool _isBoundedContext(final String name) {
  final contextDir = Directory('lib/$name');
  return contextDir.existsSync() &&
      (Directory('lib/$name/domain').existsSync() ||
          Directory('lib/$name/application').existsSync());
}

Future<BoundedContextAnalysis> _analyzeBoundedContextStructure(
  final String context,
) async {
  final violations = <String>[];

  // Required directories for proper DDD structure
  final requiredDirs = [
    'lib/$context/domain/interfaces',
    'lib/$context/domain',
    'lib/$context/application/services',
    'lib/$context/infrastructure/adapters',
  ];

  for (final dir in requiredDirs) {
    if (!Directory(dir).existsSync()) {
      violations.add('❌ Missing required directory: $dir');
    }
  }

  // Check for proper layer separation
  if (Directory('lib/$context/domain').existsSync()) {
    final domainFiles = await _findDomainFiles(context);
    for (final file in domainFiles) {
      final content = await file.readAsString();
      if (_hasInfrastructureDependencies(content)) {
        violations.add(
          '❌ Domain file has infrastructure dependencies: ${_getRelativePath(file.path)}',
        );
      }
    }
  }

  return BoundedContextAnalysis(violations: violations);
}

Future<int> _calculateContextQualityScore(final String context) async {
  var score = 0;
  final maxScore = 100;

  // Domain structure (25 points)
  if (Directory('lib/$context/domain/interfaces').existsSync()) score += 10;
  if (Directory('lib/$context/domain/models').existsSync() ||
      Directory('lib/$context/domain/entities').existsSync()) {
    score += 10;
  }
  if (await _hasProperDomainInterfaces(context)) score += 5;

  // Application structure (25 points)
  if (Directory('lib/$context/application/services').existsSync()) score += 10;
  if (Directory('lib/$context/application/use_cases').existsSync()) score += 10;
  if (await _hasWellDesignedApplicationServices(context)) score += 5;

  // Infrastructure structure (25 points)
  if (Directory('lib/$context/infrastructure/adapters').existsSync()) {
    score += 15;
  }
  if (await _hasProperInterfaceImplementations(context)) score += 10;

  // Architecture adherence (25 points)
  final isolationScore = await _calculateIsolationScore(context);
  score += isolationScore;

  return ((score / maxScore) * 100).round();
}

Future<List<DomainInterface>> _findDomainInterfaces(
  final String context,
) async {
  final interfaces = <DomainInterface>[];
  final interfacesDir = Directory('lib/$context/domain/interfaces');

  if (!interfacesDir.existsSync()) return interfaces;

  await for (final entity in interfacesDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      final interfaceNames = _extractAllInterfaceNames(content, entity.path);
      for (final interfaceName in interfaceNames) {
        interfaces.add(
          DomainInterface(
            name: interfaceName,
            filePath: entity.path,
            content: content,
          ),
        );
      }
    }
  }

  return interfaces;
}

Future<List<DomainInterface>> _findCoreInterfaces() async {
  final interfaces = <DomainInterface>[];
  final coreInterfacesDir = Directory('lib/core/interfaces');

  if (!coreInterfacesDir.existsSync()) return interfaces;

  await for (final entity in coreInterfacesDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      final interfaceNames = _extractAllInterfaceNames(content, entity.path);
      for (final interfaceName in interfaceNames) {
        interfaces.add(
          DomainInterface(
            name: interfaceName,
            filePath: entity.path,
            content: content,
          ),
        );
      }
    }
  }

  return interfaces;
}

Future<List<DomainInterface>> _findSharedInterfaces() async {
  final interfaces = <DomainInterface>[];
  final sharedInterfacesDir = Directory('lib/shared/interfaces');

  if (!sharedInterfacesDir.existsSync()) return interfaces;

  await for (final entity in sharedInterfacesDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      final interfaceNames = _extractAllInterfaceNames(content, entity.path);
      for (final interfaceName in interfaceNames) {
        interfaces.add(
          DomainInterface(
            name: interfaceName,
            filePath: entity.path,
            content: content,
          ),
        );
      }
    }
  }

  return interfaces;
}

Future<List<InfrastructureImplementation>> _findInfrastructureImplementations(
  final String context,
) async {
  final implementations = <InfrastructureImplementation>[];
  final adaptersDir = Directory('lib/$context/infrastructure/adapters');

  if (!adaptersDir.existsSync()) return implementations;

  await for (final entity in adaptersDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      final className = _extractClassName(content);
      implementations.add(
        InfrastructureImplementation(
          className: className,
          filePath: entity.path,
          content: content,
        ),
      );
    }
  }

  return implementations;
}

Future<List<File>> _findDomainFiles(final String context) async {
  final files = <File>[];
  final domainDir = Directory('lib/$context/domain');

  if (!domainDir.existsSync()) return files;

  await for (final entity in domainDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }

  return files;
}

List<String> _findInvalidDomainDependencies(
  final String content,
  final String context,
) {
  final violations = <String>[];

  // Check for imports that violate domain layer rules
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]''');
  final imports = importPattern.allMatches(content);

  for (final import in imports) {
    final importPath = import.group(1)!;

    // Invalid dependencies for domain layer
    if (importPath.contains('/infrastructure/') ||
        importPath.contains('/presentation/') ||
        importPath.contains('/application/controllers/') ||
        (_isOtherBoundedContext(importPath, context) &&
            !importPath.contains('/domain/'))) {
      violations.add(importPath);
    }
  }

  return violations;
}

bool _isOtherBoundedContext(
  final String importPath,
  final String currentContext,
) {
  final boundedContexts = _findBoundedContexts();
  return boundedContexts.any(
    (final context) =>
        context != currentContext && importPath.contains('/$context/'),
  );
}

Future<List<String>> _checkBoundedContextIsolation(
  final String context,
  final List<String> allContexts,
) async {
  final violations = <String>[];
  final otherContexts = allContexts.where((final c) => c != context).toList();

  // Check domain layer isolation
  final domainFiles = await _findDomainFiles(context);
  for (final file in domainFiles) {
    final content = await file.readAsString();
    final crossContextImports = _findCrossContextImports(
      content,
      otherContexts,
    );

    for (final import in crossContextImports) {
      violations.add(
        '❌ ${_getRelativePath(file.path)}: Domain imports from other context: $import',
      );
    }
  }

  return violations;
}

List<String> _findCrossContextImports(
  final String content,
  final List<String> forbiddenContexts,
) {
  final violations = <String>[];
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]''');
  final imports = importPattern.allMatches(content);

  for (final import in imports) {
    final importPath = import.group(1)!;

    for (final forbiddenContext in forbiddenContexts) {
      if (importPath.contains('/$forbiddenContext/')) {
        violations.add(forbiddenContext);
        break;
      }
    }
  }

  return violations;
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

Future<ServiceResponsibilityAnalysis> _analyzeServiceResponsibility(
  final File serviceFile,
) async {
  final content = await serviceFile.readAsString();
  final lines = content.split('\n');
  final methodCount = _countPublicMethods(content);
  final responsibilities = _detectResponsibilities(content);

  return ServiceResponsibilityAnalysis(
    lineCount: lines.length,
    methodCount: methodCount,
    responsibilities: responsibilities,
    hasMultipleResponsibilities: responsibilities.length > 2,
  );
}

int _countPublicMethods(final String content) {
  final methodPattern = RegExp(
    r'^\s*(?:Future<[^>]*>|void|String|int|bool|double|\w+)\s+(?!_)\w+\s*\([^)]*\)\s*(?:async\s*)?{',
    multiLine: true,
  );
  return methodPattern.allMatches(content).length;
}

List<String> _detectResponsibilities(final String content) {
  final responsibilities = <String>[];

  // Domain-specific responsibility detection
  if (content.contains('message') &&
      (content.contains('send') || content.contains('receive'))) {
    responsibilities.add('message-handling');
  }
  if (content.contains('audio') ||
      content.contains('tts') ||
      content.contains('stt')) {
    responsibilities.add('audio-processing');
  }
  if (content.contains('backup') ||
      content.contains('save') ||
      content.contains('persistence')) {
    responsibilities.add('data-persistence');
  }
  if (content.contains('image') ||
      content.contains('avatar') ||
      content.contains('photo')) {
    responsibilities.add('image-processing');
  }
  if (content.contains('memory') ||
      content.contains('timeline') ||
      content.contains('history')) {
    responsibilities.add('memory-management');
  }
  if (content.contains('validation') || content.contains('validate')) {
    responsibilities.add('validation');
  }
  if (content.contains('queue') ||
      content.contains('schedule') ||
      content.contains('timer')) {
    responsibilities.add('scheduling');
  }
  if (content.contains('call') &&
      (content.contains('start') || content.contains('end'))) {
    responsibilities.add('call-management');
  }
  if (content.contains('export') ||
      content.contains('import') ||
      content.contains('file')) {
    responsibilities.add('data-transfer');
  }

  return responsibilities;
}

Future<List<File>> _findUseCases(final String context) async {
  final useCases = <File>[];
  final useCasesDir = Directory('lib/$context/application/use_cases');

  if (!useCasesDir.existsSync()) return useCases;

  await for (final entity in useCasesDir.list()) {
    if (entity is File && entity.path.endsWith('.dart')) {
      useCases.add(entity);
    }
  }

  return useCases;
}

Future<UseCaseAnalysis> _analyzeUseCaseDesign(final File useCaseFile) async {
  final content = await useCaseFile.readAsString();
  final methodCount = _countPublicMethods(content);
  final hasInfraDeps = _hasInfrastructureDependencies(content);

  return UseCaseAnalysis(
    isTooBroad: methodCount > 3, // Use case should be focused
    hasInfrastructureDependencies: hasInfraDeps,
  );
}

bool _hasInfrastructureDependencies(final String content) {
  return content.contains('/infrastructure/') ||
      content.contains('import \'package:') &&
          content.contains('infrastructure');
}

Future<List<String>> _findAllProjectFiles() async {
  final files = <String>[];
  final libDir = Directory('lib');

  if (!libDir.existsSync()) return files;

  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity.path);
    }
  }

  return files;
}

String _determineExpectedLayer(final String filePath, final String content) {
  // Intelligent layer detection based on content analysis
  if (content.contains('abstract class') ||
      content.contains('abstract interface')) {
    return 'domain/interfaces';
  }
  if (content.contains('class') && content.contains('UseCase')) {
    return 'application/use_cases';
  }
  if (content.contains('class') && content.contains('ApplicationService')) {
    return 'application/services';
  }
  if (content.contains('class') && content.contains('Controller')) {
    return 'application/controllers';
  }
  if (content.contains('implements') && filePath.contains('infrastructure')) {
    return 'infrastructure/adapters';
  }
  if (content.contains('Widget') ||
      content.contains('StatelessWidget') ||
      content.contains('StatefulWidget')) {
    return 'presentation';
  }

  return 'unknown';
}

String _determineActualLayer(final String filePath) {
  if (filePath.contains('/domain/interfaces/')) return 'domain/interfaces';
  if (filePath.contains('/domain/models/') ||
      filePath.contains('/domain/entities/')) {
    return 'domain/models';
  }
  if (filePath.contains('/application/use_cases/')) {
    return 'application/use_cases';
  }
  if (filePath.contains('/application/services/')) {
    return 'application/services';
  }
  if (filePath.contains('/application/controllers/')) {
    return 'application/controllers';
  }
  if (filePath.contains('/infrastructure/adapters/')) {
    return 'infrastructure/adapters';
  }
  if (filePath.contains('/presentation/')) return 'presentation';

  return 'unknown';
}

Future<List<String>> _checkNamingConventions(final String context) async {
  final violations = <String>[];

  // Check interface naming
  final interfaces = await _findDomainInterfaces(context);
  for (final interface in interfaces) {
    if (!interface.name.startsWith('I') && !interface.name.endsWith('Port')) {
      violations.add(
        '❌ Interface naming: ${interface.name} should start with "I" or end with "Port"',
      );
    }
  }

  // Check application service naming
  final appServices = await _findApplicationServices(context);
  for (final service in appServices) {
    final className = _extractClassName(await service.readAsString());
    if (!className.endsWith('ApplicationService') &&
        !className.endsWith('Service')) {
      violations.add(
        '❌ Service naming: $className should end with "ApplicationService"',
      );
    }
  }

  return violations;
}

Future<List<File>> _findSharedFiles() async {
  final files = <File>[];
  final sharedDir = Directory('lib/shared');

  if (!sharedDir.existsSync()) return files;

  await for (final entity in sharedDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }

  return files;
}

bool _isAuenticlyCrossCuttingConcern(
  final String content,
  final String filePath,
) {
  // Check if it's truly a cross-cutting concern
  final crossCuttingKeywords = [
    'logging',
    'monitor',
    'metric',
    'trace',
    'audit',
    'cache',
    'config',
    'constant',
    'util',
    'helper',
    'exception',
    'error',
    'result',
    'response',
    'validation',
    'security',
    'authorization',
    'enum',
    'typedef',
    'extension',
  ];

  final lowerContent = content.toLowerCase();
  final lowerPath = filePath.toLowerCase();

  return crossCuttingKeywords.any(
    (final keyword) =>
        lowerContent.contains(keyword) || lowerPath.contains(keyword),
  );
}

// Additional helper functions
bool _implementsInterface(
  final InfrastructureImplementation impl,
  final DomainInterface interface,
) {
  // Check for explicit implements/extends
  final implementsPattern = RegExp(
    r'implements\s+[^{]*\b' + RegExp.escape(interface.name) + r'\b',
  );
  final extendsPattern = RegExp(
    r'extends\s+[^{]*\b' + RegExp.escape(interface.name) + r'\b',
  );

  if (implementsPattern.hasMatch(impl.content) ||
      extendsPattern.hasMatch(impl.content)) {
    return true;
  }

  // Fallback: class name similarity (less strict)
  final interfaceNameWithoutI = interface.name.startsWith('I')
      ? interface.name.substring(1)
      : interface.name;
  return impl.className.toLowerCase().contains(
    interfaceNameWithoutI.toLowerCase(),
  );
}

List<String> _getImplementedInterfaces(final String content) {
  final interfaces = <String>[];
  final implementsPattern = RegExp(r'implements\s+([^{]+)');
  final extendsPattern = RegExp(r'extends\s+([^{]+)');

  final implementsMatch = implementsPattern.firstMatch(content);
  if (implementsMatch != null) {
    interfaces.addAll(
      implementsMatch
          .group(1)!
          .split(',')
          .map((final s) => s.trim())
          .where((final s) => s.isNotEmpty),
    );
  }

  final extendsMatch = extendsPattern.firstMatch(content);
  if (extendsMatch != null) {
    interfaces.addAll(
      extendsMatch
          .group(1)!
          .split(',')
          .map((final s) => s.trim())
          .where((final s) => s.isNotEmpty),
    );
  }

  return interfaces;
}

bool _shouldHaveInterface(final InfrastructureImplementation impl) {
  // Infrastructure implementations should generally have interfaces
  // except for simple DTOs, utilities, or very specific adapters
  final className = impl.className.toLowerCase();
  return !className.contains('dto') &&
      !className.contains('util') &&
      !className.contains('helper') &&
      !className.contains('config');
}

List<String> _extractAllInterfaceNames(
  final String content,
  final String filePath,
) {
  final interfaces = <String>[];
  // Handle modern Dart syntax: abstract interface class IName
  final interfacePattern = RegExp(
    r'(?:abstract\s+)?(?:interface\s+)?class\s+(\w+)',
    multiLine: true,
  );
  final matches = interfacePattern.allMatches(content);

  for (final match in matches) {
    final interfaceName = match.group(1);
    if (interfaceName != null) {
      interfaces.add(interfaceName);
    }
  }

  return interfaces;
}

String _extractClassName(final String content) {
  final match = RegExp(r'class\s+(\w+)').firstMatch(content);
  return match?.group(1) ?? 'Unknown';
}

String _getRelativePath(final String path) {
  return path.replaceFirst(RegExp(r'^.*?lib/'), 'lib/');
}

// Additional helper implementations
Future<bool> _hasProperDomainInterfaces(final String context) async {
  final interfaces = await _findDomainInterfaces(context);
  return interfaces.isNotEmpty;
}

Future<bool> _hasWellDesignedApplicationServices(final String context) async {
  final services = await _findApplicationServices(context);
  if (services.isEmpty) return false;

  for (final service in services) {
    final analysis = await _analyzeServiceResponsibility(service);
    if (analysis.hasMultipleResponsibilities || analysis.methodCount > 20) {
      return false;
    }
  }
  return true;
}

Future<bool> _hasProperInterfaceImplementations(final String context) async {
  final interfaces = await _findDomainInterfaces(context);
  final coreInterfaces = await _findCoreInterfaces();
  final sharedInterfaces = await _findSharedInterfaces();
  final allInterfaces = [...interfaces, ...coreInterfaces, ...sharedInterfaces];
  final implementations = await _findInfrastructureImplementations(context);

  if (allInterfaces.isEmpty) return true; // No interfaces required

  return allInterfaces.every(
    (final interface) => implementations.any(
      (final impl) => _implementsInterface(impl, interface),
    ),
  );
}

Future<int> _calculateIsolationScore(final String context) async {
  final domainFiles = await _findDomainFiles(context);
  var violations = 0;

  for (final file in domainFiles) {
    final content = await file.readAsString();
    if (_hasInfrastructureDependencies(content)) {
      violations++;
    }
  }

  // Return score out of 25 based on isolation quality
  return violations == 0 ? 25 : (25 - (violations * 5)).clamp(0, 25);
}

// ===================================================================
// DATA CLASSES FOR ANALYSIS RESULTS
// ===================================================================

class BoundedContextAnalysis {
  const BoundedContextAnalysis({required this.violations});
  final List<String> violations;
}

class DomainInterface {
  const DomainInterface({
    required this.name,
    required this.filePath,
    required this.content,
  });

  final String name;
  final String filePath;
  final String content;
}

class InfrastructureImplementation {
  const InfrastructureImplementation({
    required this.className,
    required this.filePath,
    required this.content,
  });

  final String className;
  final String filePath;
  final String content;
}

class ServiceResponsibilityAnalysis {
  const ServiceResponsibilityAnalysis({
    required this.lineCount,
    required this.methodCount,
    required this.responsibilities,
    required this.hasMultipleResponsibilities,
  });

  final int lineCount;
  final int methodCount;
  final List<String> responsibilities;
  final bool hasMultipleResponsibilities;
}

class UseCaseAnalysis {
  const UseCaseAnalysis({
    required this.isTooBroad,
    required this.hasInfrastructureDependencies,
  });

  final bool isTooBroad;
  final bool hasInfrastructureDependencies;
}

class DuplicationAnalysis {
  const DuplicationAnalysis({
    required this.significantDuplications,
    required this.minorDuplications,
  });

  final List<DuplicationViolation> significantDuplications;
  final List<DuplicationViolation> minorDuplications;
}

class DuplicationViolation {
  const DuplicationViolation({
    required this.description,
    required this.severity,
    required this.filePaths,
  });

  final String description;
  final String severity;
  final List<String> filePaths;
}

class CommonPatternAnalysis {
  const CommonPatternAnalysis({
    required this.unabstractedPatterns,
    required this.wellAbstractedPatterns,
  });

  final List<UnabstractedPattern> unabstractedPatterns;
  final List<String> wellAbstractedPatterns;
}

class UnabstractedPattern {
  const UnabstractedPattern({
    required this.name,
    required this.occurrences,
    required this.locations,
  });

  final String name;
  final int occurrences;
  final List<String> locations;
}

class UtilityUsageAnalysis {
  const UtilityUsageAnalysis({
    required this.missedUtilizations,
    required this.wellUtilizedShared,
  });

  final List<MissedUtilization> missedUtilizations;
  final List<String> wellUtilizedShared;
}

class MissedUtilization {
  const MissedUtilization({
    required this.filePath,
    required this.utilityName,
    required this.sharedUtilityPath,
  });

  final String filePath;
  final String utilityName;
  final String sharedUtilityPath;
}

// ===================================================================
// DRY ANALYSIS HELPER FUNCTIONS
// ===================================================================

Future<DuplicationAnalysis> _analyzeDuplication(
  final List<String> files,
) async {
  final significantDuplications = <DuplicationViolation>[];
  final minorDuplications = <DuplicationViolation>[];

  // Analyze code blocks for duplication
  final codeBlocks = <String, List<String>>{};

  for (final filePath in files) {
    if (filePath.endsWith('.dart')) {
      final content = await File(filePath).readAsString();
      final blocks = _extractCodeBlocks(content, filePath);

      for (final block in blocks) {
        if (block.length > 50) {
          // Only significant blocks
          codeBlocks.putIfAbsent(block, () => []).add(filePath);
        }
      }
    }
  }

  // Find duplicated blocks
  for (final entry in codeBlocks.entries) {
    if (entry.value.length > 1) {
      final severity = entry.key.length > 200 ? 'significant' : 'minor';
      final violation = DuplicationViolation(
        description:
            'Code block duplicated across ${entry.value.length} files: ${entry.value.map(_getRelativePath).join(", ")}',
        severity: severity,
        filePaths: entry.value,
      );

      if (severity == 'significant') {
        significantDuplications.add(violation);
      } else {
        minorDuplications.add(violation);
      }
    }
  }

  // Analyze constants duplication
  final constantDuplications = await _analyzeConstantDuplication(files);
  significantDuplications.addAll(constantDuplications);

  return DuplicationAnalysis(
    significantDuplications: significantDuplications,
    minorDuplications: minorDuplications,
  );
}

Future<CommonPatternAnalysis> _analyzeCommonPatterns(
  final String context,
) async {
  final unabstractedPatterns = <UnabstractedPattern>[];
  final wellAbstractedPatterns = <String>[];

  // Analyze repository patterns
  final repositories = await _findRepositoryImplementations(context);
  final repoPatterns = _analyzeRepositoryPatterns(repositories);
  unabstractedPatterns.addAll(repoPatterns);

  // Analyze validation patterns
  final validators = await _findValidators(context);
  final validationPatterns = _analyzeValidationPatterns(validators);
  unabstractedPatterns.addAll(validationPatterns);

  // Analyze error handling patterns
  final serviceFiles = await _findApplicationServices(context);
  final services = <ApplicationService>[];
  for (final file in serviceFiles) {
    final content = await file.readAsString();
    services.add(
      ApplicationService(
        name: path.basenameWithoutExtension(file.path),
        path: file.path,
        content: content,
      ),
    );
  }
  final errorPatterns = _analyzeErrorHandlingPatterns(services);
  unabstractedPatterns.addAll(errorPatterns);

  return CommonPatternAnalysis(
    unabstractedPatterns: unabstractedPatterns,
    wellAbstractedPatterns: wellAbstractedPatterns,
  );
}

Future<UtilityUsageAnalysis> _analyzeUtilityUsage() async {
  final missedUtilizations = <MissedUtilization>[];
  final wellUtilizedShared = <String>[];

  // Find existing shared utilities
  final sharedUtils = await _findSharedUtilities();

  // Analyze if these utilities are being used instead of reimplemented
  final allFiles = await _findAllProjectFiles();

  for (final filePath in allFiles) {
    if (filePath.endsWith('.dart') && !filePath.contains('/shared/')) {
      final content = await File(filePath).readAsString();

      for (final util in sharedUtils) {
        if (_hasReimplementedUtility(content, util)) {
          missedUtilizations.add(
            MissedUtilization(
              filePath: filePath,
              utilityName: util.name,
              sharedUtilityPath: util.path,
            ),
          );
        }
      }
    }
  }

  return UtilityUsageAnalysis(
    missedUtilizations: missedUtilizations,
    wellUtilizedShared: wellUtilizedShared,
  );
}

List<String> _extractCodeBlocks(final String content, final String filePath) {
  final blocks = <String>[];
  final lines = content.split('\n');

  // Extract method bodies
  var inMethod = false;
  var methodBody = <String>[];
  var braceCount = 0;

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.contains(RegExp(r'\w+\s*\([^)]*\)\s*\{'))) {
      inMethod = true;
      methodBody = [line];
      braceCount = _countChar(line, '{') - _countChar(line, '}');
    } else if (inMethod) {
      methodBody.add(line);
      braceCount += _countChar(line, '{') - _countChar(line, '}');

      if (braceCount <= 0) {
        final blockContent = methodBody.join('\n').trim();
        if (blockContent.length > 50) {
          blocks.add(_normalizeCodeBlock(blockContent));
        }
        inMethod = false;
        methodBody.clear();
      }
    }
  }

  return blocks;
}

int _countChar(final String text, final String char) {
  return char.allMatches(text).length;
}

String _normalizeCodeBlock(final String code) {
  // Normalize whitespace and variable names for better duplicate detection
  return code
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*(?=\s*[=:])'), 'VAR')
      .toLowerCase();
}

Future<List<DuplicationViolation>> _analyzeConstantDuplication(
  final List<String> files,
) async {
  final violations = <DuplicationViolation>[];
  final constants = <String, List<String>>{};

  for (final filePath in files) {
    if (filePath.endsWith('.dart')) {
      final content = await File(filePath).readAsString();
      final fileConstants = _extractConstants(content);

      for (final constant in fileConstants) {
        constants.putIfAbsent(constant, () => []).add(filePath);
      }
    }
  }

  for (final entry in constants.entries) {
    if (entry.value.length > 2) {
      // More than 2 files have the same constant
      violations.add(
        DuplicationViolation(
          description:
              'Constant "${entry.key}" duplicated across ${entry.value.length} files - should be centralized',
          severity: 'significant',
          filePaths: entry.value,
        ),
      );
    }
  }

  return violations;
}

List<String> _extractConstants(final String content) {
  final constants = <String>[];
  final constPattern = RegExp(
    r'static\s+const\s+\w+\s*=\s*["\x27]([^"\x27]+)["\x27]',
  );
  final matches = constPattern.allMatches(content);

  for (final match in matches) {
    final value = match.group(1);
    if (value != null && value.length > 5) {
      // Only meaningful constants
      constants.add(value);
    }
  }

  return constants;
}

Future<List<RepositoryInfo>> _findRepositoryImplementations(
  final String context,
) async {
  final repositories = <RepositoryInfo>[];
  final contextPath = path.join(Directory.current.path, 'lib', context);

  if (Directory(contextPath).existsSync()) {
    await for (final entity in Directory(contextPath).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final content = await entity.readAsString();
        if (content.contains('Repository') && content.contains('class')) {
          repositories.add(
            RepositoryInfo(
              name: path.basenameWithoutExtension(entity.path),
              path: entity.path,
              content: content,
            ),
          );
        }
      }
    }
  }

  return repositories;
}

List<UnabstractedPattern> _analyzeRepositoryPatterns(
  final List<RepositoryInfo> repositories,
) {
  final patterns = <UnabstractedPattern>[];
  final crudMethods = <String, List<String>>{};

  for (final repo in repositories) {
    final methods = _extractCrudMethods(repo.content);
    for (final method in methods) {
      crudMethods.putIfAbsent(method, () => []).add(repo.name);
    }
  }

  for (final entry in crudMethods.entries) {
    if (entry.value.length > 2) {
      patterns.add(
        UnabstractedPattern(
          name: 'CRUD method "${entry.key}"',
          occurrences: entry.value.length,
          locations: entry.value,
        ),
      );
    }
  }

  return patterns;
}

List<String> _extractCrudMethods(final String content) {
  final methods = <String>[];
  final patterns = [
    r'Future<\w*>\s+create\w*\(',
    r'Future<\w*>\s+update\w*\(',
    r'Future<\w*>\s+delete\w*\(',
    r'Future<\w*>\s+find\w*\(',
    r'Future<\w*>\s+get\w*\(',
  ];

  for (final pattern in patterns) {
    final matches = RegExp(pattern).allMatches(content);
    for (final match in matches) {
      methods.add(match.group(0) ?? '');
    }
  }

  return methods;
}

Future<List<ValidatorInfo>> _findValidators(final String context) async {
  final validators = <ValidatorInfo>[];
  final contextPath = path.join(Directory.current.path, 'lib', context);

  if (Directory(contextPath).existsSync()) {
    await for (final entity in Directory(contextPath).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final content = await entity.readAsString();
        if (content.contains('Validator') || content.contains('validate')) {
          validators.add(
            ValidatorInfo(
              name: path.basenameWithoutExtension(entity.path),
              path: entity.path,
              content: content,
            ),
          );
        }
      }
    }
  }

  return validators;
}

List<UnabstractedPattern> _analyzeValidationPatterns(
  final List<ValidatorInfo> validators,
) {
  final patterns = <UnabstractedPattern>[];
  final validationLogic = <String, List<String>>{};

  for (final validator in validators) {
    final logic = _extractValidationLogic(validator.content);
    for (final logicBlock in logic) {
      validationLogic.putIfAbsent(logicBlock, () => []).add(validator.name);
    }
  }

  for (final entry in validationLogic.entries) {
    if (entry.value.length > 2) {
      patterns.add(
        UnabstractedPattern(
          name: 'Validation logic pattern',
          occurrences: entry.value.length,
          locations: entry.value,
        ),
      );
    }
  }

  return patterns;
}

List<String> _extractValidationLogic(final String content) {
  final logic = <String>[];
  final patterns = [
    r'if\s*\([^)]*\.isEmpty\)',
    r'if\s*\([^)]*\.length\s*[<>]\s*\d+\)',
    r'if\s*\([^)]*\.contains\(',
    r'throw\s+\w*Exception\(',
  ];

  for (final pattern in patterns) {
    final matches = RegExp(pattern).allMatches(content);
    for (final match in matches) {
      logic.add(_normalizeCodeBlock(match.group(0) ?? ''));
    }
  }

  return logic.toSet().toList(); // Remove duplicates within same file
}

List<UnabstractedPattern> _analyzeErrorHandlingPatterns(
  final List<ApplicationService> services,
) {
  final patterns = <UnabstractedPattern>[];
  final errorHandling = <String, List<String>>{};

  for (final service in services) {
    final errorBlocks = _extractErrorHandling(service.content);
    for (final block in errorBlocks) {
      errorHandling.putIfAbsent(block, () => []).add(service.name);
    }
  }

  for (final entry in errorHandling.entries) {
    if (entry.value.length > 2) {
      patterns.add(
        UnabstractedPattern(
          name: 'Error handling pattern',
          occurrences: entry.value.length,
          locations: entry.value,
        ),
      );
    }
  }

  return patterns;
}

List<String> _extractErrorHandling(final String content) {
  final patterns = <String>[];
  final errorPatterns = [
    r'try\s*\{[^}]*\}\s*catch\s*\([^)]*\)\s*\{[^}]*\}',
    r'if\s*\([^)]*\)\s*throw\s+\w*Exception\(',
    r'return\s+Result\.failure\(',
    r'return\s+Either\.left\(',
  ];

  for (final pattern in errorPatterns) {
    final matches = RegExp(pattern, dotAll: true).allMatches(content);
    for (final match in matches) {
      patterns.add(_normalizeCodeBlock(match.group(0) ?? ''));
    }
  }

  return patterns.toSet().toList(); // Remove duplicates within same file
}

Future<List<SharedUtility>> _findSharedUtilities() async {
  final utilities = <SharedUtility>[];
  final sharedPath = path.join(Directory.current.path, 'lib', 'shared');

  if (Directory(sharedPath).existsSync()) {
    await for (final entity in Directory(sharedPath).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final content = await entity.readAsString();
        final utilityFunctions = _extractUtilityFunctions(content);

        for (final funcName in utilityFunctions) {
          utilities.add(
            SharedUtility(name: funcName, path: entity.path, content: content),
          );
        }
      }
    }
  }

  return utilities;
}

List<String> _extractUtilityFunctions(final String content) {
  final functions = <String>[];
  final functionPattern = RegExp(
    r'(?:static\s+)?(?:\w+\s+)?(\w+)\s*\([^)]*\)\s*\{',
  );
  final matches = functionPattern.allMatches(content);

  for (final match in matches) {
    final funcName = match.group(1);
    if (funcName != null &&
        !funcName.startsWith('_') &&
        funcName != 'build' &&
        funcName != 'main' &&
        funcName != 'initState' &&
        funcName != 'dispose' &&
        funcName.length > 3 &&
        // Must be camelCase (start with lowercase, contain uppercase)
        RegExp(r'^[a-z][a-zA-Z0-9]*[A-Z]').hasMatch(funcName)) {
      functions.add(funcName);
    }
  }

  return functions;
}

bool _hasReimplementedUtility(
  final String content,
  final SharedUtility utility,
) {
  // Ignore basic Dart keywords and common patterns
  final ignoredKeywords = {
    'if',
    'catch',
    'try',
    'for',
    'while',
    'switch',
    'case',
    'return',
    'throw',
    'new',
    'this',
    'super',
    'async',
    'await',
    'final',
    'const',
    'var',
    'bool',
    'int',
    'String',
    'double',
    'List',
    'Map',
    'Set',
  };

  if (ignoredKeywords.contains(utility.name.toLowerCase())) {
    return false;
  }

  // Only check for utilities that are actual function names (camelCase, not single words)
  if (utility.name.length < 3 ||
      !RegExp(r'^[a-z][a-zA-Z0-9]*[A-Z]').hasMatch(utility.name)) {
    return false;
  }

  // Check if the file contains a function implementation similar to the utility
  // but doesn't import the shared utility
  final functionPattern = RegExp('\\b${utility.name}\\s*\\(');
  final importPattern = RegExp("import\\s+['\"].*shared.*['\"]");

  // Only flag if there's a function definition (not just usage) and no import
  final hasDefinition =
      functionPattern.hasMatch(content) && content.contains('${utility.name}(');
  final hasImport = importPattern.hasMatch(content);

  return hasDefinition && !hasImport;
} // Additional data classes for DRY analysis

class RepositoryInfo {
  const RepositoryInfo({
    required this.name,
    required this.path,
    required this.content,
  });
  final String name;
  final String path;
  final String content;
}

class ValidatorInfo {
  const ValidatorInfo({
    required this.name,
    required this.path,
    required this.content,
  });
  final String name;
  final String path;
  final String content;
}

class SharedUtility {
  const SharedUtility({
    required this.name,
    required this.path,
    required this.content,
  });
  final String name;
  final String path;
  final String content;
}

class ApplicationService {
  const ApplicationService({
    required this.name,
    required this.path,
    required this.content,
  });
  final String name;
  final String path;
  final String content;
}
