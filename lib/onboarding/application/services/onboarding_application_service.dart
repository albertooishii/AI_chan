import '../use_cases/generate_next_question_use_case.dart';
import '../use_cases/process_user_response_use_case.dart';
import '../../domain/entities/memory_data.dart';

/// 🎯 **Application Service** coordinador para el módulo de Onboarding
///
/// Siguiendo el patrón DDD, actúa como **Facade** que coordina
/// múltiples Use Cases y mantiene el **SRP** (Single Responsibility Principle).
///
/// **Responsabilidades:**
/// - Coordinar flujo conversacional de onboarding
/// - Gestionar generación de biografías y perfiles
/// - Manejar importación/exportación de datos
/// - Mantener coherencia entre use cases
///
/// **Principios DDD implementados:**
/// - ✅ Application Service como coordinador
/// - ✅ Dependency Inversion (depende de abstracciones)
/// - ✅ Single Responsibility (solo coordinación)
/// - ✅ Open/Closed (extensible sin modificación)
class OnboardingApplicationService {
  // Nota: Los Use Cases actuales son static, pero mantenemos el patrón DDD
  // para futura refactorización hacia dependency injection

  const OnboardingApplicationService();

  /// 🗣️ **Flujo Conversacional Completo**
  /// Coordina el proceso completo de onboarding conversacional
  Future<OnboardingConversationResult> processConversationalFlow({
    required final MemoryData currentMemory,
    required final String userResponse,
  }) async {
    try {
      // 1. Procesar respuesta del usuario
      final response = await ProcessUserResponseUseCase.execute(
        currentMemory: currentMemory,
        userResponse: userResponse,
      );

      // Extraer datos del response
      final updatedMemory = response['updatedMemory'] as MemoryData;
      final error = response['error'] as bool? ?? false;

      if (error) {
        throw OnboardingApplicationException('Error procesando respuesta: ${response['exception']}');
      }

      // 2. Verificar si el onboarding está completo
      final missingData = updatedMemory.getMissingData();
      if (missingData.isEmpty) {
        // Onboarding completo - generar biografía si es necesario
        return OnboardingConversationResult(
          memory: updatedMemory,
          aiResponse: response['aiResponse'] as String?,
          isComplete: true,
        );
      }

      // 3. Si no está completo, generar siguiente pregunta
      final nextQuestion = await GenerateNextQuestionUseCase.execute(
        currentMemory: updatedMemory,
        lastUserResponse: userResponse,
      );

      return OnboardingConversationResult(memory: updatedMemory, aiResponse: nextQuestion, isComplete: false);
    } catch (e) {
      throw OnboardingApplicationException('Error en flujo conversacional: ${e.toString()}');
    }
  }

  /// � **Generar Siguiente Pregunta**
  /// Coordina la generación de la siguiente pregunta del onboarding
  Future<String> generateNextQuestion({required final MemoryData currentMemory, final String? lastUserResponse}) async {
    try {
      return await GenerateNextQuestionUseCase.execute(
        currentMemory: currentMemory,
        lastUserResponse: lastUserResponse,
      );
    } catch (e) {
      throw OnboardingApplicationException('Error generando siguiente pregunta: ${e.toString()}');
    }
  }

  /// � **Reiniciar Onboarding**
  /// Coordina el reinicio completo del proceso de onboarding
  Future<void> resetOnboarding() async {
    try {
      // Limpiar estado estático (temporal hasta refactorizar ProcessUserResponseUseCase)
      ProcessUserResponseUseCase.clearConversationHistory();

      // TODO: Cuando eliminemos el estado estático, esto se manejará via repositorio
    } catch (e) {
      throw OnboardingApplicationException('Error reiniciando onboarding: ${e.toString()}');
    }
  }

  /// 🧠 **Obtener Estado de Memoria**
  /// Coordina la obtención del estado actual de la memoria
  MemoryData getMemoryState() {
    // Por ahora retornamos memoria vacía, en el futuro esto vendrá del repositorio
    return const MemoryData();
  }

  /// ✅ **Verificar Completitud del Onboarding**
  /// Coordina la verificación de si el onboarding está completo
  bool isOnboardingComplete(final MemoryData memory) {
    return memory.getMissingData().isEmpty;
  }

  /// � **Obtener Progreso del Onboarding**
  /// Coordina el cálculo del progreso del onboarding
  OnboardingProgress getProgress(final MemoryData memory) {
    final missingData = memory.getMissingData();
    final totalFields = 6; // userName, userCountry, userBirthdate, aiCountry, aiName, meetStory
    final completedFields = totalFields - missingData.length;

    return OnboardingProgress(
      completedFields: completedFields,
      totalFields: totalFields,
      progressPercentage: (completedFields / totalFields) * 100,
      nextRequiredField: missingData.isNotEmpty ? missingData.first : null,
    );
  }
}

/// 📊 **Resultado del Flujo Conversacional**
class OnboardingConversationResult {

  const OnboardingConversationResult({required this.memory, this.aiResponse, required this.isComplete});
  final MemoryData memory;
  final String? aiResponse;
  final bool isComplete;
}

/// 📈 **Progreso del Onboarding**
class OnboardingProgress {

  const OnboardingProgress({
    required this.completedFields,
    required this.totalFields,
    required this.progressPercentage,
    this.nextRequiredField,
  });
  final int completedFields;
  final int totalFields;
  final double progressPercentage;
  final String? nextRequiredField;
}

/// ❌ **Excepción de Application Service**
class OnboardingApplicationException implements Exception {
  const OnboardingApplicationException(this.message);
  final String message;

  @override
  String toString() => 'OnboardingApplicationException: $message';
}
