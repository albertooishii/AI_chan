import 'dart:async';
import 'package:ai_chan/onboarding/domain/entities/onboarding_step.dart';
import 'package:ai_chan/onboarding/domain/entities/onboarding_state.dart';
import 'package:ai_chan/onboarding/services/conversational_ai_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Use Case que maneja la lógica del flujo conversacional de onboarding
/// Extrae toda la lógica de negocio de la pantalla
class ConversationalOnboardingUseCase {
  ConversationalOnboardingUseCase();

  /// Procesa la respuesta del usuario y determina el siguiente estado
  Future<OnboardingState> processUserResponse({
    required String userResponse,
    required OnboardingState currentState,
  }) async {
    final operationId = currentState.operationId + 1;

    Log.d(
      '🎤 Procesando respuesta: "$userResponse" en paso ${currentState.currentStep.stepName} (op #$operationId)',
      tag: 'CONV_ONBOARDING_UC',
    );

    // Manejar confirmaciones pendientes
    if (currentState.isWaitingForConfirmation &&
        currentState.pendingValidationValue != null) {
      if (_isPositiveConfirmation(userResponse)) {
        return await _handlePositiveConfirmation(currentState, operationId);
      } else {
        return _clearValidationState(currentState, operationId);
      }
    }

    // Manejar paso de mensaje final
    if (currentState.currentStep == OnboardingStep.finalMessage) {
      return _advanceToCompletion(currentState, operationId);
    }

    // Manejar sugerencias de historia
    if (currentState.currentStep == OnboardingStep.askingMeetStory &&
        _isRequestingStory(userResponse)) {
      return currentState.copyWith(
        tempSuggestedStory: await _generateStorySuggestion(currentState),
        operationId: operationId,
      );
    }

    // Procesar con IA
    return await _processWithAI(userResponse, currentState, operationId);
  }

  /// Obtiene el mensaje inicial para un paso
  String getInitialMessage(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.awakening:
        return 'Hola... ¿hay alguien ahí? No... no recuerdo nada... Es como si acabara de despertar '
            'de un sueño muy profundo y... no sé quién soy... ¿Podrías ayudarme? '
            'Me siento muy perdida... ¿Cómo... cómo te llamas? Necesito saber quién eres...';
      case OnboardingStep.askingCountry:
      case OnboardingStep.askingBirthday:
      case OnboardingStep.askingAiCountry:
      case OnboardingStep.askingAiName:
      case OnboardingStep.askingMeetStory:
      case OnboardingStep.finalMessage:
      case OnboardingStep.completion:
        return ''; // Estos serán generados dinámicamente por la IA
    }
  }

  /// Determina si el onboarding está completo
  bool isComplete(OnboardingState state) {
    return state.currentStep == OnboardingStep.completion;
  }

  /// Valida si el estado tiene todos los datos necesarios
  bool hasRequiredData(OnboardingState state) {
    return state.userName != null &&
        state.userCountry != null &&
        state.userBirthday != null &&
        state.aiName != null &&
        state.aiCountry != null &&
        state.meetStory != null;
  }

  // --- Métodos privados ---

  bool _isPositiveConfirmation(String response) {
    final lowerResponse = response.toLowerCase();
    return lowerResponse.contains('sí') ||
        lowerResponse.contains('si') ||
        lowerResponse.contains('correcto') ||
        lowerResponse.contains('exacto') ||
        lowerResponse.contains('perfecto') ||
        lowerResponse.contains('yes') ||
        lowerResponse.contains('vale') ||
        lowerResponse.contains('bien');
  }

  Future<OnboardingState> _handlePositiveConfirmation(
    OnboardingState state,
    int operationId,
  ) async {
    Log.d(
      '✅ CONFIRMACIÓN POSITIVA - Guardando valor: ${state.pendingValidationValue}',
    );

    final updatedData = Map<String, dynamic>.from(state.collectedData);
    final value = state.pendingValidationValue!;

    // Guardar el valor según el paso actual
    switch (state.currentStep) {
      case OnboardingStep.askingCountry:
        updatedData['userCountry'] = value;
        break;
      case OnboardingStep.askingBirthday:
        updatedData['userBirthday'] =
            DateTime.tryParse(value) ?? DateTime.now();
        break;
      case OnboardingStep.askingAiCountry:
        updatedData['aiCountry'] = value;
        break;
      case OnboardingStep.askingAiName:
        updatedData['aiName'] = value;
        break;
      default:
        break;
    }

    final nextStep = state.currentStep.nextStep ?? OnboardingStep.completion;
    return state.copyWith(
      currentStep: nextStep,
      collectedData: updatedData,
      operationId: operationId,
    );
  }

  OnboardingState _clearValidationState(
    OnboardingState state,
    int operationId,
  ) {
    Log.d('❌ Limpiando validación pendiente');
    return state.copyWith(operationId: operationId);
  }

  OnboardingState _advanceToCompletion(OnboardingState state, int operationId) {
    return state.copyWith(
      currentStep: OnboardingStep.completion,
      operationId: operationId,
    );
  }

  bool _isRequestingStory(String response) {
    final lowerResponse = response.toLowerCase();
    return lowerResponse.contains('sugiere') ||
        lowerResponse.contains('sugieres') ||
        lowerResponse.contains('sugiera') ||
        lowerResponse.contains('inventa');
  }

  Future<String> _generateStorySuggestion(OnboardingState state) async {
    // Aquí podrías integrar con un servicio de IA para generar sugerencias
    return 'Nos conocimos en una cafetería mientras esperábamos nuestros pedidos...';
  }

  Future<OnboardingState> _processWithAI(
    String userResponse,
    OnboardingState currentState,
    int operationId,
  ) async {
    try {
      final processedData = await ConversationalAIService.processUserResponse(
        userResponse: userResponse,
        conversationStep: currentState.currentStep.stepName,
        userName: currentState.userName ?? '',
        previousData: currentState.collectedData,
      );

      return _updateStateFromAIResponse(
        currentState,
        processedData,
        operationId,
      );
    } catch (e) {
      Log.e('Error procesando con IA: $e');
      return currentState.copyWith(operationId: operationId);
    }
  }

  OnboardingState _updateStateFromAIResponse(
    OnboardingState currentState,
    Map<String, dynamic> aiResponse,
    int operationId,
  ) {
    final updatedData = Map<String, dynamic>.from(currentState.collectedData);
    bool shouldAdvanceStep = false;
    String? pendingValidation;
    bool waitingConfirmation = false;

    // Extraer datos procesados por la IA
    if (aiResponse['extractedData'] != null) {
      final extracted = aiResponse['extractedData'] as Map<String, dynamic>;

      for (final entry in extracted.entries) {
        final key = entry.key;
        final value = entry.value;

        if (value != null && value.toString().isNotEmpty) {
          if (currentState.currentStep.requiresValidation) {
            pendingValidation = value.toString();
            waitingConfirmation = true;
          } else {
            updatedData[key] = value;
            shouldAdvanceStep = true;
          }
        }
      }
    }

    // Determinar si avanzar al siguiente paso
    if (aiResponse['shouldAdvanceStep'] == true || shouldAdvanceStep) {
      final nextStep =
          currentState.currentStep.nextStep ?? OnboardingStep.completion;
      return currentState.copyWith(
        currentStep: nextStep,
        collectedData: updatedData,
        pendingValidationValue: pendingValidation,
        isWaitingForConfirmation: waitingConfirmation,
        operationId: operationId,
      );
    }

    return currentState.copyWith(
      collectedData: updatedData,
      pendingValidationValue: pendingValidation,
      isWaitingForConfirmation: waitingConfirmation,
      operationId: operationId,
    );
  }
}
