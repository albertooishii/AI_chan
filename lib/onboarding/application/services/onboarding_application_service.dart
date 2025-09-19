import 'package:ai_chan/onboarding/application/use_cases/generate_next_question_use_case.dart';
import 'package:ai_chan/onboarding/application/use_cases/process_user_response_use_case.dart';
import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';

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
  OnboardingApplicationService({final dynamic aiProviderManager})
    : _aiProviderManager = aiProviderManager;

  final dynamic _aiProviderManager;

  /// 💾 **Estado de la conversación**
  /// Gestión centralizada del historial conversacional siguiendo DDD
  final List<Map<String, String>> _conversationHistory = [];

  /// 📝 **Gestión de Historial de Conversación**
  ///
  /// Métodos para manejar el estado conversacional centralizado
  void addConversationEntry(final String key, final String value) {
    _conversationHistory.add({key: value});
  }

  List<Map<String, String>> getConversationHistory() {
    return List.from(_conversationHistory);
  }

  void clearConversationHistory() {
    _conversationHistory.clear();
  }

  /// 🗣️ **Flujo Conversacional Completo**
  /// Coordina el proceso completo de onboarding conversacional
  Future<OnboardingConversationResult> processConversationalFlow({
    required final MemoryData currentMemory,
    required final String userResponse,
    final dynamic aiProviderManager, // Para testing
  }) async {
    try {
      // 1. Procesar respuesta del usuario
      final response = await ProcessUserResponseUseCase.execute(
        currentMemory: currentMemory,
        userResponse: userResponse,
        conversationHistory: getConversationHistory(),
        addToHistory: addConversationEntry,
        aiProviderManager: _aiProviderManager,
      );

      // Extraer datos del response
      final updatedMemory = response['updatedMemory'] as MemoryData;
      final error = response['error'] as bool? ?? false;

      if (error) {
        throw OnboardingApplicationException(
          'Error procesando respuesta: ${response['exception']}',
        );
      }

      // 2. Verificar si el onboarding está completo
      final missingData = updatedMemory.getMissingData();
      if (missingData.isEmpty) {
        // Onboarding completo - generar biografía si es necesario
        return OnboardingConversationResult(
          memory: updatedMemory,
          aiResponse: response['aiResponse'] as String?,
          isComplete: true,
          success: true,
          extractedDataType: response['extractedData']?['type'] as String?,
          extractedDataValue: response['extractedData']?['value'] as String?,
        );
      }

      // 3. Si no está completo, usar aiResponse del JSON (ya incluye la siguiente pregunta)
      return OnboardingConversationResult(
        memory: updatedMemory,
        aiResponse: response['aiResponse'] as String?,
        isComplete: false,
        success: true,
        extractedDataType: response['extractedData']?['type'] as String?,
        extractedDataValue: response['extractedData']?['value'] as String?,
      );
    } catch (e) {
      throw OnboardingApplicationException(
        'Error en flujo conversacional: ${e.toString()}',
      );
    }
  }

  /// � **Generar Siguiente Pregunta**
  /// Coordina la generación de la siguiente pregunta del onboarding
  Future<String> generateNextQuestion({
    required final MemoryData currentMemory,
    final String? lastUserResponse,
  }) async {
    try {
      return await GenerateNextQuestionUseCase.execute(
        currentMemory: currentMemory,
        lastUserResponse: lastUserResponse,
      );
    } catch (e) {
      throw OnboardingApplicationException(
        'Error generando siguiente pregunta: ${e.toString()}',
      );
    }
  }

  /// � **Reiniciar Onboarding**
  /// Coordina el reinicio completo del proceso de onboarding
  Future<void> resetOnboarding() async {
    try {
      // Limpiar estado del historial conversacional
      clearConversationHistory();

      // Estado ahora gestionado en Application Service siguiendo DDD
    } catch (e) {
      throw OnboardingApplicationException(
        'Error reiniciando onboarding: ${e.toString()}',
      );
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
    final totalFields =
        6; // userName, userCountry, userBirthdate, aiCountry, aiName, meetStory
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
  const OnboardingConversationResult({
    required this.memory,
    this.aiResponse,
    required this.isComplete,
    required this.success,
    this.extractedDataType,
    this.extractedDataValue,
    this.error,
  });

  final MemoryData memory;
  final String? aiResponse;
  final bool isComplete;
  final bool success;
  final String? extractedDataType;
  final String? extractedDataValue;
  final String? error;

  /// Getter para compatibilidad con API existente
  MemoryData get updatedMemory => memory;
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
