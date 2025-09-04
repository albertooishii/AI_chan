# Ejemplo de Uso: Arquitectura Refactorizada

## Componentes Creados

### 1. **Domain Layer - Entidades de Dominio**

**OnboardingStep**: Enum que define los pasos del onboarding con lógica de negocio
```dart
// Ejemplo de uso
final currentStep = OnboardingStep.askingName;
print(currentStep.stepName); // "askingName" 
print(currentStep.requiresValidation); // true
final nextStep = currentStep.nextStep(); // OnboardingStep.askingCountry
```

**OnboardingState**: Estado inmutable que contiene datos recopilados
```dart
// Crear estado inicial
final state = OnboardingState(
  currentStep: OnboardingStep.askingName,
  collectedData: {},
);

// Actualizar estado
final newState = state.copyWith(
  currentStep: OnboardingStep.askingCountry,
  collectedData: {'userName': 'Alberto'},
);
```

### 2. **Application Layer - Casos de Uso y Servicios**

**ConversationalOnboardingUseCase**: Procesa respuestas y maneja transiciones de estado
```dart
// Procesar respuesta del usuario
final result = await useCase.processUserResponse(
  userResponse: "Mi nombre es Alberto",
  currentState: state,
);

// Resultado incluye estado actualizado y valor extraído
print(result.updatedState.userName); // "Alberto"
print(result.extractedValue); // "Alberto"  
print(result.shouldAdvance); // true
```

**VoiceConfigurationService**: Configura la voz según el estado del onboarding
```dart
// Obtener configuración de voz
final voiceConfig = service.getVoiceConfiguration(state);
print(voiceConfig.accentInstructions); // Instrucciones específicas del país
```

### 3. **Presentation Layer - Controlador**

**ConversationalOnboardingController**: Coordina la lógica de presentación
```dart
// Procesar respuesta del usuario
await controller.processUserResponse("Soy de España");

// El controlador automáticamente:
// - Procesa la respuesta usando el caso de uso
// - Actualiza el estado
// - Genera respuesta de la IA
// - Configura TTS con acento correcto
// - Notifica a la UI
```

## Beneficios de la Nueva Arquitectura

### ✅ **Separación de Responsabilidades**
- **Domain**: Reglas de negocio puras, sin dependencias externas
- **Application**: Casos de uso y servicios de aplicación
- **Presentation**: Solo manejo de UI y estados de interfaz

### ✅ **Testabilidad Mejorada**
- Cada componente se puede testear independientemente
- Use cases puros sin dependencias de UI
- Estado inmutable facilita testing

### ✅ **Reusabilidad**
- Los use cases pueden ser reutilizados en diferentes pantallas
- Estado de dominio independiente de la UI
- Servicios de aplicación desacoplados

### ✅ **Mantenibilidad**
- Reducción de 1,548 líneas a componentes específicos
- Lógica de negocio extraída de la UI
- Dependencias inyectadas correctamente

## Comparación: Antes vs Después

### Antes (Monolítico)
```
conversational_onboarding_screen.dart (1,548 líneas)
├── UI + Lógica de Negocio + Estado + Servicios
├── Métodos privados gigantes
├── Estado mutable disperso
└── Difícil de testear y mantener
```

### Después (Clean Architecture)
```
Domain Layer
├── onboarding_step.dart (43 líneas)
└── onboarding_state.dart (58 líneas)

Application Layer  
├── conversational_onboarding_use_case.dart (285 líneas)
├── voice_configuration_service.dart (75 líneas)
└── conversational_onboarding_controller.dart (320 líneas)

Presentation Layer
└── conversational_onboarding_screen_refactored.dart (421 líneas)
```

## Integración con el Sistema Existente

La nueva arquitectura es **completamente compatible** con el sistema existente:

- Utiliza la misma interfaz `OnboardingFinishCallback`
- Integra con `OnboardingProvider` existente  
- Funciona con servicios TTS/STT actuales
- Mantiene la funcionalidad de subtítulos conversacionales

## Próximos Pasos Recomendados

1. **Migrar gradualmente** otras pantallas usando este patrón
2. **Crear tests unitarios** para cada componente
3. **Extraer más servicios** de aplicación para otros flujos
4. **Establecer este patrón** como estándar para nuevas funcionalidades
