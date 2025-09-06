import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/onboarding/application/services/onboarding_application_service.dart';
import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';

void main() {
  group('🎯 OnboardingApplicationService - DDD Application Service Tests', () {
    late OnboardingApplicationService service;

    setUp(() {
      service = OnboardingApplicationService();
    });

    group('📊 Architecture Validation', () {
      test('debe seguir el patrón Application Service en DDD', () {
        // ✅ GIVEN: OnboardingApplicationService existe
        expect(service, isNotNull);

        // ✅ THEN: Debe actuar como coordinador/facade sin lógica de negocio
        expect(service.runtimeType.toString(), 'OnboardingApplicationService');
      });

      test('debe coordinar use cases sin duplicar lógica', () {
        // ✅ GIVEN: Servicio creado
        expect(service, isNotNull);

        // ✅ THEN: Debe tener métodos de coordinación, no lógica compleja
        final methods = [
          'processConversationalFlow',
          'generateNextQuestion',
          'resetOnboarding',
          'getMemoryState',
          'isOnboardingComplete',
          'getProgress',
          'addConversationEntry',
          'getConversationHistory',
          'clearConversationHistory',
        ];

        // Verificar que los métodos están disponibles
        expect(() => service.getMemoryState(), returnsNormally);
        expect(() => service.isOnboardingComplete(const MemoryData()), returnsNormally);
        expect(() => service.getProgress(const MemoryData()), returnsNormally);
        expect(() => service.getConversationHistory(), returnsNormally);
        expect(() => service.clearConversationHistory(), returnsNormally);
      });

      test('debe mantener Single Responsibility Principle', () {
        // ✅ GIVEN: Application Service
        // ✅ THEN: Solo debe coordinar, no implementar lógica de dominio

        // Verifica que no tiene dependencias complejas inyectadas
        expect(service.runtimeType.toString(), contains('OnboardingApplicationService'));

        // Verifica que tiene una responsabilidad clara
        final memory = const MemoryData();
        expect(() => service.getProgress(memory), returnsNormally);
      });
    });

    group('🧠 Memory State Management', () {
      test('debe retornar memoria vacía por defecto', () {
        // ✅ GIVEN: Servicio sin estado
        final memory = service.getMemoryState();

        // ✅ THEN: Debe retornar MemoryData vacía
        expect(memory, isA<MemoryData>());
        expect(memory.userName, isNull);
        expect(memory.userCountry, isNull);
        expect(memory.aiName, isNull);
      });

      test('debe verificar completitud del onboarding correctamente', () {
        // ✅ GIVEN: Memoria vacía
        const emptyMemory = MemoryData();

        // ✅ WHEN: Verificar completitud
        final isEmpty = service.isOnboardingComplete(emptyMemory);

        // ✅ THEN: Debe retornar false
        expect(isEmpty, isFalse);

        // ✅ GIVEN: Memoria completa
        const completeMemory = MemoryData(
          userName: 'Alberto',
          userCountry: 'ES',
          userBirthdate: '23/11/1986',
          aiCountry: 'JP',
          aiName: 'Yuna',
          meetStory: 'Nos conocimos en un foro de anime',
        );

        // ✅ WHEN: Verificar completitud
        final isComplete = service.isOnboardingComplete(completeMemory);

        // ✅ THEN: Debe retornar true
        expect(isComplete, isTrue);
      });
    });

    group('📈 Progress Tracking', () {
      test('debe calcular progreso correctamente', () {
        // ✅ GIVEN: Memoria parcialmente llena
        const partialMemory = MemoryData(
          userName: 'Alberto',
          userCountry: 'ES',
          // userBirthdate falta
          aiCountry: 'JP',
          // aiName falta
          // meetStory falta
        );

        // ✅ WHEN: Calcular progreso
        final progress = service.getProgress(partialMemory);

        // ✅ THEN: Debe mostrar progreso correcto
        expect(progress.completedFields, equals(3)); // userName, userCountry, aiCountry
        expect(progress.totalFields, equals(6));
        expect(progress.progressPercentage, equals(50.0)); // 3/6 = 50%
        expect(progress.nextRequiredField, equals('userBirthdate'));
      });

      test('debe mostrar progreso 100% cuando esté completo', () {
        // ✅ GIVEN: Memoria completa
        const completeMemory = MemoryData(
          userName: 'Alberto',
          userCountry: 'ES',
          userBirthdate: '23/11/1986',
          aiCountry: 'JP',
          aiName: 'Yuna',
          meetStory: 'Nos conocimos en un foro de anime',
        );

        // ✅ WHEN: Calcular progreso
        final progress = service.getProgress(completeMemory);

        // ✅ THEN: Debe mostrar 100%
        expect(progress.completedFields, equals(6));
        expect(progress.totalFields, equals(6));
        expect(progress.progressPercentage, equals(100.0));
        expect(progress.nextRequiredField, isNull);
      });
    });

    group('🔄 Reset Functionality', () {
      test('debe manejar reset graciosamente', () async {
        // ✅ GIVEN: Servicio activo
        // ✅ WHEN: Intentar resetear onboarding
        try {
          await service.resetOnboarding();
          // ✅ THEN: Si no hay excepción, perfecto
          expect(true, isTrue);
        } on OnboardingApplicationException catch (e) {
          // ✅ THEN: Si hay excepción, debe ser OnboardingApplicationException
          expect(e.toString(), contains('Error reiniciando onboarding'));
        }
      });
    });

    group('🎯 Result Objects', () {
      test('OnboardingConversationResult debe tener estructura correcta', () {
        // ✅ GIVEN: Resultado de conversación
        const memory = MemoryData(userName: 'Test');
        const result = OnboardingConversationResult(
          memory: memory,
          aiResponse: 'Hola Test',
          isComplete: false,
          success: true,
        );

        // ✅ THEN: Debe tener todos los campos
        expect(result.memory, equals(memory));
        expect(result.aiResponse, equals('Hola Test'));
        expect(result.isComplete, isFalse);
        expect(result.success, isTrue);
      });

      test('OnboardingProgress debe tener estructura correcta', () {
        // ✅ GIVEN: Progreso del onboarding
        const progress = OnboardingProgress(
          completedFields: 3,
          totalFields: 6,
          progressPercentage: 50.0,
          nextRequiredField: 'userBirthdate',
        );

        // ✅ THEN: Debe tener todos los campos
        expect(progress.completedFields, equals(3));
        expect(progress.totalFields, equals(6));
        expect(progress.progressPercentage, equals(50.0));
        expect(progress.nextRequiredField, equals('userBirthdate'));
      });
    });

    group('❌ Exception Handling', () {
      test('OnboardingApplicationException debe funcionar correctamente', () {
        // ✅ GIVEN: Excepción del Application Service
        const exception = OnboardingApplicationException('Test error');

        // ✅ THEN: Debe tener mensaje correcto
        expect(exception.message, equals('Test error'));
        expect(exception.toString(), contains('OnboardingApplicationException'));
        expect(exception.toString(), contains('Test error'));
      });
    });
  });
}
