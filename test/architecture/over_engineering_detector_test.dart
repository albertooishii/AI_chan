import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('🚫 Over-Engineering Detection', () {
    test('🔍 Detect unnecessary interface wrappers', () async {
      final violations = await _detectUnnecessaryInterfaces();

      if (violations.isNotEmpty) {
        final report = _generateOverEngineeringReport(violations);
        print(report);
        fail(
          '❌ Found ${violations.length} over-engineering violations. '
          'See report above for details.',
        );
      }

      print('✅ No over-engineering violations detected');
    });

    test('🔍 Detect wrapper services without added value', () async {
      final violations = await _detectWrapperServices();

      if (violations.isNotEmpty) {
        final report = _generateWrapperReport(violations);
        print(report);
        print(
          'ℹ️  Note: Only well-known over-engineering patterns are flagged as errors.',
        );
        print(
          '   Other potential issues are shown for informational purposes.',
        );
      }

      print('✅ No known over-engineering wrapper patterns detected');
    });

    test('🔍 Detect premature abstractions', () async {
      final violations = await _detectPrematureAbstractions();

      if (violations.isNotEmpty) {
        final report = _generateAbstractionReport(violations);
        print(report);
        print(
          'ℹ️  Note: These are potential over-engineering patterns detected automatically.',
        );
        print(
          '   Review each case to determine if simplification is appropriate.',
        );
      }

      print('✅ Over-engineering detection completed');
    });
  });
}

/// Detecta interfaces que solo tienen una implementación y no agregan valor
Future<List<OverEngineeringViolation>> _detectUnnecessaryInterfaces() async {
  final violations = <OverEngineeringViolation>[];
  final interfaceDir = Directory('lib');

  // Buscar todos los archivos que definen interfaces
  final interfaceFiles = await _findInterfaceFiles(interfaceDir);

  for (final file in interfaceFiles) {
    final content = await file.readAsString();
    final interfaceName = _extractInterfaceName(content, file.path);

    if (interfaceName == null) continue;

    // Buscar implementaciones de esta interfaz
    final implementations = await _findImplementations(interfaceName);

    // Verificar si es sobre-ingeniería
    if (_isUnnecessaryInterface(interfaceName, implementations, content)) {
      violations.add(
        OverEngineeringViolation(
          type: OverEngineeringType.unnecessaryInterface,
          file: file.path,
          interfaceName: interfaceName,
          implementations: implementations,
          description:
              'Interface with single implementation that only delegates',
          recommendation: 'Use direct implementation or utility class',
        ),
      );
    }
  }

  return violations;
}

/// Detecta servicios que solo actúan como wrappers sin agregar valor
Future<List<OverEngineeringViolation>> _detectWrapperServices() async {
  final violations = <OverEngineeringViolation>[];
  final serviceDir = Directory('lib');

  await for (final file in serviceDir.list(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      final content = await file.readAsString();

      // Detectar servicios que solo delegan
      if (_isWrapperService(content, file.path)) {
        final serviceName = _extractClassName(content, file.path);

        violations.add(
          OverEngineeringViolation(
            type: OverEngineeringType.wrapperService,
            file: file.path,
            interfaceName: serviceName,
            implementations: [],
            description:
                'Service that only delegates to other services/utilities',
            recommendation: 'Use the underlying service/utility directly',
          ),
        );
      }
    }
  }

  return violations;
}

/// Detecta abstracciones creadas prematuramente sin uso real
Future<List<OverEngineeringViolation>> _detectPrematureAbstractions() async {
  final violations = <OverEngineeringViolation>[];
  final libDir = Directory('lib');

  await for (final file in libDir.list(recursive: true)) {
    if (file is File &&
        file.path.endsWith('.dart') &&
        file.path.contains('/interfaces/')) {
      final content = await file.readAsString();
      final interfaceName = _extractInterfaceName(content, file.path);

      if (interfaceName == null) continue;

      // Detectar interfaces que empiezan con "I" y tienen características de sobre-ingeniería
      if (interfaceName.startsWith('I') &&
          _isPrematureInterface(content, interfaceName)) {
        violations.add(
          OverEngineeringViolation(
            type: OverEngineeringType.prematureAbstraction,
            file: file.path,
            interfaceName: interfaceName,
            implementations: [],
            description: 'Interface with over-engineering characteristics',
            recommendation:
                'Consider using direct implementation or utility class',
          ),
        );
      }
    }
  }

  return violations;
}

/// Encuentra archivos que contienen definiciones de interfaces
Future<List<File>> _findInterfaceFiles(Directory dir) async {
  final files = <File>[];

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();

      // Buscar patrones de definición de interfaces
      if (content.contains('abstract class I') ||
          content.contains('abstract interface class') ||
          (entity.path.contains('/interfaces/') &&
              content.contains('abstract class'))) {
        files.add(entity);
      }
    }
  }

  return files;
}

/// Extrae el nombre de la interfaz del contenido del archivo
String? _extractInterfaceName(String content, String filePath) {
  // Buscar patrones de definición de interfaces
  final patterns = [
    RegExp(r'abstract class (I[A-Z][a-zA-Z]*)\s'),
    RegExp(r'abstract interface class ([A-Z][a-zA-Z]*)\s'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(content);
    if (match != null) {
      return match.group(1);
    }
  }

  return null;
}

/// Extrae el nombre de la clase del contenido del archivo
String? _extractClassName(String content, String filePath) {
  final pattern = RegExp(r'class ([A-Z][a-zA-Z]*)\s');
  final match = pattern.firstMatch(content);
  return match?.group(1);
}

/// Encuentra implementaciones de una interfaz
Future<List<String>> _findImplementations(String interfaceName) async {
  final implementations = <String>[];
  final libDir = Directory('lib');

  await for (final file in libDir.list(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      final content = await file.readAsString();

      // Buscar implementaciones
      if (content.contains('implements $interfaceName') ||
          content.contains('extends $interfaceName')) {
        final className = _extractClassName(content, file.path);
        if (className != null) {
          implementations.add(className);
        }
      }
    }
  }

  return implementations;
}

/// Determina si una interfaz es innecesaria
bool _isUnnecessaryInterface(
  String interfaceName,
  List<String> implementations,
  String content,
) {
  // Patrones de sobre-ingeniería conocidos
  final overEngineeredPatterns = [
    'ISharedLogger',
    'IChatLogger',
    'ILoggingService',
    'IBackupService',
    'IPreferencesService',
    'INetworkService',
    'IChatPromiseService',
    'IChatAudioUtilsService',
    'INavigationService',
    'IRecordingService',
    'IUIStateService',
  ];

  // Si está en la lista de patrones conocidos de sobre-ingeniería
  if (overEngineeredPatterns.contains(interfaceName)) {
    return true;
  }

  // Si solo tiene una implementación y métodos simples
  if (implementations.length <= 1) {
    // Verificar si los métodos son triviales (solo delegación)
    final methodCount = _countMethods(content);
    final trivialMethods = _countTrivialMethods(content);

    if (methodCount > 0 && trivialMethods / methodCount > 0.7) {
      return true;
    }
  }

  return false;
}

/// Determina si un servicio es solo un wrapper
bool _isWrapperService(String content, String filePath) {
  // 1. Detectar clases que empiezan con "Basic" (patrón común de wrapper)
  if (_isBasicWrapper(content)) {
    return true;
  }

  // 2. Detectar alta ratio de delegación con poca lógica propia
  if (_isHighDelegationLowLogic(content)) {
    return true;
  }

  // 3. Detectar servicios que solo tienen métodos que llaman a otros servicios
  if (_isOnlyServiceCalls(content)) {
    return true;
  }

  return false;
}

/// Cuenta métodos en una clase/interfaz
int _countMethods(String content) {
  final methodPattern = RegExp(
    r'\s+(void|Future|String|int|bool|double|\w+)\s+\w+\s*\(',
  );
  return methodPattern.allMatches(content).length;
}

/// Cuenta métodos triviales (solo return o delegación simple)
int _countTrivialMethods(String content) {
  final trivialPatterns = [
    RegExp(r'{\s*return\s+\w+\.\w+\([^}]*\);\s*}'), // return other.method()
    RegExp(r'{\s*\w+\.\w+\([^}]*\);\s*}'), // other.method()
    RegExp(r'=>\s*\w+\.\w+\([^;]*\);'), // => other.method()
  ];

  int count = 0;
  for (final pattern in trivialPatterns) {
    count += pattern.allMatches(content).length;
  }

  return count;
}

/// Cuenta métodos que solo delegan a otros servicios
int _countDelegationMethods(String content) {
  final delegationPatterns = [
    RegExp(r'return\s+_\w+\.\w+\('), // return _service.method(
    RegExp(r'return\s+\w+\.\w+\('), // return service.method(
    RegExp(r'_\w+\.\w+\(.*\);'), // _service.method();
    RegExp(r'=>\s*_\w+\.\w+\('), // => _service.method(
  ];

  int count = 0;
  for (final pattern in delegationPatterns) {
    count += pattern.allMatches(content).length;
  }

  return count;
}

/// Cuenta líneas con lógica (no solo delegación)
int _countLogicLines(String content) {
  final logicPatterns = [
    RegExp(r'if\s*\('), // if statements
    RegExp(r'for\s*\('), // for loops
    RegExp(r'while\s*\('), // while loops
    RegExp(r'switch\s*\('), // switch statements
    RegExp(r'await\s+\w+'), // await calls
    RegExp(r'final\s+\w+\s*='), // variable assignments
    RegExp(r'return\s+[^_\w]'), // return with logic (not just delegation)
  ];

  int count = 0;
  for (final pattern in logicPatterns) {
    count += pattern.allMatches(content).length;
  }

  return count;
}

/// Verifica si un servicio solo delega
bool _isOnlyDelegating(String content) {
  final methodCount = _countMethods(content);
  final delegationCount = _countDelegationMethods(content);

  return methodCount > 0 && delegationCount / methodCount > 0.9;
}

/// Cuenta métodos abstractos en una interfaz
int _countAbstractMethods(String content) {
  final abstractMethodPattern = RegExp(
    r'\s+(void|Future|String|int|bool|double|\w+)\s+\w+\s*\([^)]*\)\s*;',
  );
  return abstractMethodPattern.allMatches(content).length;
}

/// Verifica si solo tiene métodos triviales
bool _hasOnlyTrivialMethods(String content) {
  final trivialPatterns = [
    RegExp(r'void\s+\w+\s*\(\s*\)\s*;'), // void method();
    RegExp(r'String\s+get\s+\w+\s*;'), // String get property;
    RegExp(r'bool\s+\w+\s*\(\s*\)\s*;'), // bool method();
  ];

  for (final pattern in trivialPatterns) {
    if (pattern.hasMatch(content)) {
      return true;
    }
  }

  return false;
}

/// Determina si una interfaz es prematura basado en patrones
bool _isPrematureInterface(String content, String interfaceName) {
  // 1. Interfaces con nombres que sugieren utilidades simples
  if (_isUtilityInterfaceName(interfaceName) &&
      _hasSimpleImplementation(content)) {
    return true;
  }

  // 2. Interfaces que solo definen métodos muy básicos
  if (_hasOnlyTrivialMethods(content) && _countAbstractMethods(content) <= 2) {
    return true;
  }

  // 3. Interfaces con solo getters/setters simples
  if (_isOnlyGettersSetters(content)) {
    return true;
  }

  return false;
}

/// Detecta nombres que sugieren interfaces de utilidad
bool _isUtilityInterfaceName(String interfaceName) {
  // Interfaces que terminan en patrones utilitarios
  final utilityEndings = [
    'Logger',
    'Logging',
    'Backup',
    'Preferences',
    'Network',
  ];

  for (final ending in utilityEndings) {
    if (interfaceName.contains(ending)) {
      return true;
    }
  }

  return false;
}

/// Verifica si tiene implementación simple (pocos métodos abstractos)
bool _hasSimpleImplementation(String content) {
  final abstractMethods = _countAbstractMethods(content);
  return abstractMethods <= 3;
}

/// Verifica si solo tiene getters y setters
bool _isOnlyGettersSetters(String content) {
  final getterSetterPattern = RegExp(r'\s+(get|set)\s+\w+');
  final getterSetterCount = getterSetterPattern.allMatches(content).length;
  final totalMethods = _countAbstractMethods(content);

  return totalMethods > 0 && getterSetterCount / totalMethods > 0.7;
}

/// Detecta wrappers "Basic"
bool _isBasicWrapper(String content) {
  return content.contains('class Basic') &&
      content.contains('Service') &&
      _isOnlyDelegating(content);
}

/// Detecta servicios de coordinación legítimos que NO deben marcarse como wrappers
bool _isLegitimateCoordinationService(String content) {
  // 1. Debe tener lógica condicional (if, ternary operators, switch)
  final conditionalLogic = _countConditionalLogic(content);

  // 2. Debe tener transformación/procesamiento de datos
  final dataTransformation = _hasDataTransformation(content);

  // 3. Debe coordinar entre múltiples servicios con valor agregado
  final coordinatesServices = _coordinatesMultipleServices(content);

  // Un servicio de coordinación legítimo debe tener al menos 2 de estas características
  final legitimacyScore =
      (conditionalLogic > 0 ? 1 : 0) +
      (dataTransformation ? 1 : 0) +
      (coordinatesServices ? 1 : 0);

  return legitimacyScore >= 2;
}

/// Cuenta lógica condicional (if, ternary, switch)
int _countConditionalLogic(String content) {
  final conditionalPatterns = [
    RegExp(r'if\s*\('), // if statements
    RegExp(r'\?\s*\w+\s*:'), // ternary operators
    RegExp(r'switch\s*\('), // switch statements
    RegExp(r'&&\s*\w+'), // logical AND
    RegExp(r'\|\|\s*\w+'), // logical OR
  ];

  int count = 0;
  for (final pattern in conditionalPatterns) {
    count += pattern.allMatches(content).length;
  }
  return count;
}

/// Detecta transformación/procesamiento de datos (no solo pass-through)
bool _hasDataTransformation(String content) {
  final transformationPatterns = [
    RegExp(r'await\s+\w+\.'), // async calls
    RegExp(r'final\s+\w+\s*=.*\?'), // null-safe operations
    RegExp(r'enableImageGeneration\s*\?'), // capability decisions
    RegExp(r'\?\s*AICapability\.'), // enum decisions
    RegExp(r'imageBase64\s*\?\?'), // null coalescing
    RegExp(r'resolvedImageBase64'), // data resolution
  ];

  for (final pattern in transformationPatterns) {
    if (pattern.hasMatch(content)) {
      return true;
    }
  }
  return false;
}

/// Detecta coordinación entre múltiples servicios con valor agregado
bool _coordinatesMultipleServices(String content) {
  // Buscar patrones de coordinación real, no solo delegación
  final coordinationPatterns = [
    RegExp(
      r'_\w+\s*\.\s*\w+.*await.*_\w+\s*\.\s*\w+',
    ), // múltiples servicios en secuencia
    RegExp(
      r'ImagePersistenceService.*AIProviderManager',
    ), // servicios específicos coordinados
    RegExp(
      r'_factory\.fromAIResponse.*response.*sender',
    ), // transformación de respuesta
  ];

  for (final pattern in coordinationPatterns) {
    if (pattern.hasMatch(content)) {
      return true;
    }
  }

  // También verificar si usa múltiples servicios inyectados
  final serviceFields = RegExp(
    r'final\s+\w+\s+_\w+;',
  ).allMatches(content).length;
  return serviceFields >= 2;
}

/// Detecta alta delegación con poca lógica
bool _isHighDelegationLowLogic(String content) {
  // NUEVO: Excluir servicios de coordinación legítimos
  if (_isLegitimateCoordinationService(content)) {
    return false;
  }

  final totalMethods = _countMethods(content);
  final delegationCount = _countDelegationMethods(content);
  final logicLines = _countLogicLines(content);

  // Muy estricto: >95% delegación, pocos métodos, casi sin lógica
  return totalMethods > 0 &&
      totalMethods <= 3 &&
      delegationCount / totalMethods > 0.95 &&
      logicLines <= 1;
}

/// Detecta servicios que solo hacen llamadas a otros servicios
bool _isOnlyServiceCalls(String content) {
  // NUEVO: Excluir servicios de coordinación legítimos
  if (_isLegitimateCoordinationService(content)) {
    return false;
  }

  final serviceCallPattern = RegExp(r'_\w+\.\w+\(');
  final serviceCallCount = serviceCallPattern.allMatches(content).length;
  final totalMethods = _countMethods(content);

  return totalMethods > 0 &&
      totalMethods <= 2 &&
      serviceCallCount >= totalMethods;
}

/// Genera reporte de violaciones de sobre-ingeniería
String _generateOverEngineeringReport(
  List<OverEngineeringViolation> violations,
) {
  final buffer = StringBuffer();

  buffer.writeln();
  buffer.writeln('🚫 OVER-ENGINEERING VIOLATIONS DETECTED');
  buffer.writeln('=' * 80);
  buffer.writeln('📊 Total violations: ${violations.length}');
  buffer.writeln();

  final groupedByType = <OverEngineeringType, List<OverEngineeringViolation>>{};
  for (final violation in violations) {
    groupedByType.putIfAbsent(violation.type, () => []).add(violation);
  }

  for (final entry in groupedByType.entries) {
    buffer.writeln(
      '📁 ${_getTypeDescription(entry.key)}: ${entry.value.length} violations',
    );
    for (final violation in entry.value) {
      buffer.writeln('   ❌ ${violation.interfaceName} (${violation.file})');
      buffer.writeln('      💡 ${violation.recommendation}');
    }
    buffer.writeln();
  }

  buffer.writeln('🎯 RECOMMENDATIONS:');
  buffer.writeln('   1. Remove unnecessary interfaces');
  buffer.writeln('   2. Use direct utility/service calls');
  buffer.writeln('   3. Apply YAGNI principle (You Aren\'t Gonna Need It)');
  buffer.writeln('   4. Prefer composition over premature abstraction');

  return buffer.toString();
}

/// Genera reporte de servicios wrapper
String _generateWrapperReport(List<OverEngineeringViolation> violations) {
  final buffer = StringBuffer();

  buffer.writeln();
  buffer.writeln('🎭 WRAPPER SERVICE VIOLATIONS');
  buffer.writeln('=' * 80);

  for (final violation in violations) {
    buffer.writeln('❌ ${violation.interfaceName} (${violation.file})');
    buffer.writeln('   💡 ${violation.recommendation}');
  }

  return buffer.toString();
}

/// Genera reporte de abstracciones prematuras
String _generateAbstractionReport(List<OverEngineeringViolation> violations) {
  final buffer = StringBuffer();

  buffer.writeln();
  buffer.writeln('🚧 PREMATURE ABSTRACTION VIOLATIONS');
  buffer.writeln('=' * 80);

  for (final violation in violations) {
    buffer.writeln('❌ ${violation.interfaceName} (${violation.file})');
    buffer.writeln(
      '   Implementations: ${violation.implementations.join(", ")}',
    );
    buffer.writeln('   💡 ${violation.recommendation}');
  }

  return buffer.toString();
}

String _getTypeDescription(OverEngineeringType type) {
  switch (type) {
    case OverEngineeringType.unnecessaryInterface:
      return 'Unnecessary Interfaces';
    case OverEngineeringType.wrapperService:
      return 'Wrapper Services';
    case OverEngineeringType.prematureAbstraction:
      return 'Premature Abstractions';
  }
}

/// Tipos de violaciones de sobre-ingeniería
enum OverEngineeringType {
  unnecessaryInterface,
  wrapperService,
  prematureAbstraction,
}

/// Representación de una violación de sobre-ingeniería
class OverEngineeringViolation {
  OverEngineeringViolation({
    required this.type,
    required this.file,
    this.interfaceName,
    required this.implementations,
    required this.description,
    required this.recommendation,
  });
  final OverEngineeringType type;
  final String file;
  final String? interfaceName;
  final List<String> implementations;
  final String description;
  final String recommendation;
}
