import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';
import 'package:ai_chan/onboarding/domain/services/conversational_memory_domain_service.dart';
import 'package:ai_chan/onboarding/application/services/onboarding_application_service.dart';
import 'package:ai_chan/onboarding/application/use_cases/generate_next_question_use_case.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/onboarding_fallback_utils.dart';

/// Servicio refactorizado que implementa DDD/Hexagonal Architecture
/// para el onboarding conversacional.
///
/// **REFACTORIZACIÓN DDD**: Ahora delega al OnboardingApplicationService
/// Este servicio actúa como compatibilidad con la API existente.
class ConversationalOnboardingService {
  /// 🎯 **Application Service** siguiendo DDD
  static final _applicationService = OnboardingApplicationService();

  /// Texto inicial del flujo de "despertar".
  static const String initialMessage =
      'Hola... ¿hay alguien ahí? No... no recuerdo nada... Es como si acabara de despertar '
      'de un sueño muy profundo y... no sé dónde estoy, ni quién soy, ni... ni quién eres tú... '
      'Pero... pero tengo la sensación de que te conozco de alguna manera... ¿Cómo... cómo te llamas? '
      'Por favor, ayúdame a recordar...';

  /// Mensaje de fallback cuando hay un error en el sistema/servidor
  static const String systemErrorFallback =
      'Disculpa, hay un problema en mi sistema. Vamos a intentar continuar...';

  /// Mensaje alternativo de emergencia para pedir ayuda al usuario
  static const String systemErrorAskForHelp =
      'Mi sistema tiene problemas. ¿Podrías ayudarme diciéndome algo para poder continuar?';

  /// Instancia del dominio service para validaciones
  // static final _domainService = ConversationalMemoryDomainService();

  /// Procesa la respuesta del usuario identificando automáticamente qué dato se obtuvo
  /// Retorna el dato actualizado y la siguiente respuesta de la IA
  static Future<Map<String, dynamic>> processUserResponse({
    required final MemoryData currentMemory,
    required final String userResponse,
  }) async {
    Log.d(
      '🔍 [ONB_SERVICE] Iniciando procesamiento de respuesta del usuario',
      tag: 'ONB_SERVICE',
    );

    try {
      // ✅ DDD: Delegar al OnboardingApplicationService
      final result = await _applicationService.processConversationalFlow(
        currentMemory: currentMemory,
        userResponse: userResponse,
      );

      Log.d(
        '✅ [ONB_SERVICE] Procesamiento completado exitosamente',
        tag: 'ONB_SERVICE',
      );

      // Convertir resultado del Application Service al formato esperado
      return {
        'updatedMemory': result.updatedMemory,
        'extractedData': {
          'type': result.extractedDataType,
          'value': result.extractedDataValue,
        },
        'aiResponse': result.aiResponse,
        'error': !result.success,
        'exception': result.error,
      };
    } on Exception catch (e) {
      Log.e(
        '❌ [ONB_SERVICE] Error en processUserResponse: $e',
        tag: 'ONB_SERVICE',
      );
      return _createErrorResponse(
        'Error procesando respuesta',
        currentMemory,
        userResponse,
      );
    }
  }

  /// Genera la siguiente pregunta basada en el estado actual de la memoria
  static Future<String> generateNextQuestion({
    required final MemoryData currentMemory,
    final String? lastUserResponse,
  }) async {
    Log.d('🔍 [ONB_SERVICE] Generando siguiente pregunta', tag: 'ONB_SERVICE');

    try {
      // Delegar al caso de uso de aplicación
      final result = await GenerateNextQuestionUseCase.execute(
        currentMemory: currentMemory,
        lastUserResponse: lastUserResponse,
      );

      Log.d(
        '✅ [ONB_SERVICE] Pregunta generada exitosamente',
        tag: 'ONB_SERVICE',
      );
      return result;
    } on Exception catch (e) {
      Log.e(
        '❌ [ONB_SERVICE] Error en generateNextQuestion: $e',
        tag: 'ONB_SERVICE',
      );
      return OnboardingFallbackUtils.getFallbackQuestion(currentMemory);
    }
  }

  /// Valida y actualiza un dato específico en la memoria
  static Future<MemoryData> validateAndUpdateMemory({
    required final MemoryData currentMemory,
    required final String dataType,
    required final String value,
  }) async {
    Log.d(
      '🔍 [ONB_SERVICE] Validando y actualizando memoria: $dataType=$value',
      tag: 'ONB_SERVICE',
    );

    try {
      // Usar el servicio de dominio para validación
      final validationResult =
          ConversationalMemoryDomainService.validateAndSaveData(
            dataType,
            value,
          );

      if (validationResult['isValid'] == true) {
        final validatedValue = validationResult['validatedValue'] as String?;

        // Actualizar la memoria con el valor validado
        switch (dataType) {
          case 'userName':
            return currentMemory.copyWith(userName: validatedValue);
          case 'userCountry':
            return currentMemory.copyWith(userCountry: validatedValue);
          case 'userBirthdate':
            return currentMemory.copyWith(userBirthdate: validatedValue);
          case 'aiCountry':
            return currentMemory.copyWith(aiCountry: validatedValue);
          case 'aiName':
            return currentMemory.copyWith(aiName: validatedValue);
          case 'meetStory':
            return currentMemory.copyWith(meetStory: validatedValue);
          default:
            return currentMemory;
        }
      } else {
        Log.e(
          '❌ [ONB_SERVICE] Validación falló: ${validationResult['message']}',
          tag: 'ONB_SERVICE',
        );
        return currentMemory; // Retornar memoria sin cambios si la validación falla
      }
    } on Exception catch (e) {
      Log.e('❌ [ONB_SERVICE] Error validando memoria: $e', tag: 'ONB_SERVICE');
      return currentMemory; // Retornar memoria sin cambios en caso de error
    }
  }

  /// Obtiene las instrucciones de voz para el TTS según el estado del onboarding
  static String getVoiceInstructions({
    final String? userCountry,
    final String? aiCountry,
  }) {
    // Usar el servicio de dominio para obtener instrucciones de voz
    return ConversationalMemoryDomainService.getVoiceInstructions(
      userCountry: userCountry,
      aiCountry: aiCountry,
    );
  }

  /// Verifica si la memoria está completa
  static bool isMemoryComplete(final MemoryData memory) {
    return memory.isComplete();
  }

  /// Obtiene el porcentaje de completitud de la memoria
  static double getMemoryCompletionPercentage(final MemoryData memory) {
    return memory.getCompletionPercentage();
  }

  /// Obtiene lista de datos faltantes en la memoria
  static List<String> getMissingData(final MemoryData memory) {
    return memory.getMissingData();
  }

  /// Limpia el historial de conversación (reset del onboarding)
  static void clearConversationHistory() {
    // ✅ DDD: Delegar al Application Service
    _applicationService.clearConversationHistory();
    Log.d(
      '🗣️ [ONB_SERVICE] Historial de conversación limpiado',
      tag: 'ONB_SERVICE',
    );
  }

  /// Crea una memoria vacía para iniciar el onboarding
  static MemoryData createEmptyMemory() {
    return const MemoryData();
  }

  // Métodos de compatibilidad con la API anterior

  /// Método de compatibilidad para generateNextResponse
  /// Mapea a generateNextQuestion
  static Future<String> generateNextResponse({
    required final MemoryData currentMemory,
    required final String userLastResponse,
    final bool isFirstMessage = false,
  }) async {
    if (isFirstMessage) {
      return initialMessage;
    }

    return await generateNextQuestion(
      currentMemory: currentMemory,
      lastUserResponse: userLastResponse,
    );
  }

  /// Método de compatibilidad para validateAndSaveData
  /// Mapea al servicio de dominio
  static Map<String, dynamic> validateAndSaveData(
    final String stepName,
    final String extractedValue,
  ) {
    return ConversationalMemoryDomainService.validateAndSaveData(
      stepName,
      extractedValue,
    );
  }

  /// Método de compatibilidad para generateMeetStoryFromContext
  /// Mapea al caso de uso de generación de historias
  static Future<String> generateMeetStoryFromContext({
    required final String userName,
    required final String aiName,
    final String? userCountry,
    final String? aiCountry,
    final DateTime? userBirthdate,
  }) async {
    // ✅ DDD: Delegar al Application Service para generación de biografías
    // Por ahora, devolvemos un story básico hasta implementar en Application Service
    return 'Historia de encuentro generada entre $userName y $aiName';
  }

  /// Crea una respuesta de error consistente
  static Map<String, dynamic> _createErrorResponse(
    final String? exception,
    final MemoryData currentMemory,
    final String userResponse,
  ) {
    return {
      'updatedMemory': currentMemory,
      'extractedData': {'type': null, 'value': null},
      'aiResponse': systemErrorFallback,
      'error': true,
      'exception': exception,
    };
  }
}
