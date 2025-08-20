# Plan de Migración DDD + Hexagonal - Guía Completa

**📅 Fecha:** 2025-08-20  
**🎯 Objetivo:** Migración completa a arquitectura DDD + Hexagonal por bounded contexts  
**🌿 Branch:** `migration`

---

## 📋 RESUMEN EJECUTIVO

### Bounded Contexts identificados:
1. **Chat** - Conversaciones y mensajes
2. **Onboarding** - Registro de usuario y generación de perfil  
3. **Voice/Calls** - Llamadas de voz y audio en tiempo real
4. **Core** - Shared ke**Estado:** FASE 1 ✅ COMPLETADA | FASE 2 🎉 95% COMPLETADA (Chat ✅ + Onboarding ✅ + Voice ✅ + Shared 🔄) | FASE 3 ⏳ PREPARANDO

Bounded Contexts completados: **3.5 de 4** (Chat ✅, Onboarding ✅, Voice ✅, Shared 🔄 iniciado) - Siguientes: Core cleanup final

### Objetivos de la migración:
- ✅ **Fase 1:** Infraestructura DDD básica (Config, DI, Runtime Factory)
- 🔄 **Fase 2:** Reorganización por bounded contexts (EN CURSO)
- ⏳ **Fase 3:** Refinamiento y optimización final

---

## 🎯 FASE 1: INFRAESTRUCTURA DDD BÁSICA (COMPLETADA ✅)

### 1.1 Configuración centralizada
- [x] **Crear `lib/core/config.dart`**
  - [x] Funciones `require*()` para variables críticas (fail-fast)
  - [x] Funciones `get*()` con fallbacks para variables opcionales
  - [x] Sistema de overrides para testing (`Config.setOverrides`)
  - [x] Documentar variables en `.env.example`

- [x] **Migrar lecturas de configuración**
  - [x] Eliminar `dotenv.env[...]` dispersas en el código
  - [x] Centralizar en `Config` toda lectura de environment
  - [x] Verificar que solo `config.dart` lee directamente de dotenv

### 1.2 Factory pattern para runtimes
- [x] **Crear `lib/core/runtime_factory.dart`**
  - [x] Único punto autorizado para instanciar `OpenAIService()`/`GeminiService()`
  - [x] Sistema de singletons por modelo
  - [x] Cache de instancias para reutilización

- [x] **Eliminar instanciaciones directas**
  - [x] Buscar y eliminar `new OpenAIService()` fuera del factory
  - [x] Buscar y eliminar `new GeminiService()` fuera del factory
  - [x] Verificar con test de regresión estática

### 1.3 Dependency Injection centralizado
- [x] **Refactorizar `lib/core/di.dart`**
  - [x] Composition root centralizado
  - [x] Factories por bounded context (chat, profile, voice)
  - [x] Wiring de dependencias usando Config y RuntimeFactory
  - [x] Singletons apropiados por servicio

- [x] **Actualizar adaptadores**
  - [x] `OpenAIAdapter` acepta runtime inyectado
  - [x] `GeminiAdapter` acepta runtime inyectado
  - [x] Adaptadores de perfil usan inyección
  - [x] Adaptadores TTS/STT configurables

### 1.4 Testing y regresión
- [x] **Tests de infraestructura**
  - [x] `test/core/config_test.dart` - Testing de configuración
  - [x] `test/core/runtime_factory_test.dart` - Testing del factory
  - [x] Tests de adaptadores con mocks inyectados

- [x] **Tests de regresión**
  - [x] `test/migration/check_runtime_instantiation_test.dart`
  - [x] `test/migration/import_sanity_test.dart`
  - [x] Verificación automática de violaciones

### 1.5 CI/CD Pipeline
- [x] **Implementar `.github/workflows/ci.yml`**
  - [x] Job `analyze`: flutter analyze
  - [x] Job `regression`: tests de migración específicos
  - [x] Job `test`: suite completa con coverage
  - [x] Cache de dependencias para optimización

---

## 🔄 FASE 2: REORGANIZACIÓN POR BOUNDED CONTEXTS (EN CURSO)

### 2.1 Estructura de carpetas objetivo
```
lib/
├── main.dart
├── shared/                    # Shared kernel
│   ├── constants/
│   ├── utils/
│   └── widgets/              # UI components compartidos
├── core/                     # Infraestructura compartida
│   ├── config.dart
│   ├── di.dart
│   ├── runtime_factory.dart
│   ├── interfaces/          # Ports del shared kernel
│   ├── models/              # Domain models compartidos
│   └── services/            # Domain services compartidos
├── chat/                    # Chat bounded context
│   ├── domain/
│   │   ├── models/         # Chat domain models
│   │   ├── interfaces/     # Chat ports
│   │   └── services/       # Chat domain services
│   ├── infrastructure/     # Chat adapters
│   │   ├── adapters/
│   │   └── repositories/
│   ├── application/        # Chat use cases
│   │   └── providers/      # Chat providers/controllers
│   └── presentation/       # Chat UI
│       ├── screens/
│       └── widgets/
├── onboarding/             # Onboarding bounded context
│   ├── domain/
│   ├── infrastructure/
│   ├── application/
│   └── presentation/
└── voice/                  # Voice/Calls bounded context
    ├── domain/
    ├── infrastructure/
    ├── application/
    └── presentation/
```

### 2.2 Chat Bounded Context ✅ COMPLETADO
- [x] **Chat Domain (`lib/chat/domain/`)** ✅
  - [x] Crear `lib/chat/domain/models/`
    - [x] Migrar `lib/models/chat_message.dart` → `lib/chat/domain/models/message.dart`
    - [x] Migrar `lib/models/chat_event.dart` → `lib/chat/domain/models/chat_event.dart` 
    - [x] Crear `chat_conversation.dart` aggregate
  - [x] Crear `lib/chat/domain/interfaces/`
    - [x] Migrar `IChatRepository` desde `lib/core/interfaces/`
    - [x] Migrar `IChatResponseService` desde `lib/core/interfaces/`
    - [x] Añadir `IChatService` para casos de uso
  - [x] Crear `lib/chat/domain/services/`
    - [x] Migrar `memory_summary_service.dart` (re-export por compatibilidad)
    - [x] Crear servicios de validación de chat

- [x] **Chat Infrastructure (`lib/chat/infrastructure/`)** ✅
  - [x] Crear `lib/chat/infrastructure/repositories/`
    - [x] Migrar `lib/chat/repositories/local_chat_repository.dart`
  - [x] Crear `lib/chat/infrastructure/adapters/`
    - [x] Migrar `lib/chat/services/adapters/ai_chat_response_adapter.dart`
    - [x] Migrar `lib/services/ai_chat_response_service.dart` (copiado para reorganización futura)

- [x] **Chat Application (`lib/chat/application/`)** ✅
  - [x] Migrar `lib/providers/chat_provider.dart` → `lib/chat/application/providers/chat_provider.dart`
  - [x] Casos de uso preparados para futura implementación:
    - [x] `send_message_use_case.dart` (esqueleto)
    - [x] `load_chat_history_use_case.dart` (esqueleto)
    - [x] `export_chat_use_case.dart` (esqueleto)
    - [x] `import_chat_use_case.dart` (esqueleto)

- [x] **Chat Presentation (`lib/chat/presentation/`)** ✅
  - [x] Migrar `lib/screens/chat_screen.dart` → `lib/chat/presentation/screens/chat_screen.dart`
  - [x] Migrar widgets específicos de chat:
    - [x] `lib/widgets/chat_bubble.dart` → `lib/chat/presentation/widgets/chat_bubble.dart`
    - [x] `lib/widgets/message_input.dart` → `lib/chat/presentation/widgets/message_input.dart`
    - [x] `lib/widgets/tts_configuration_dialog.dart` → `lib/chat/presentation/widgets/tts_configuration_dialog.dart`

- [x] **Chat Backward Compatibility (`lib/screens/`, `lib/widgets/`, `lib/providers/`)** ✅
  - [x] Crear re-exports transparentes en ubicaciones originales
  - [x] Verificar que todos los imports existentes funcionan sin cambios
  - [x] Mantener API pública idéntica durante migración

- [x] **Chat Testing** ✅ 
  - [x] Todos los tests existentes pasan sin modificación
  - [x] Cobertura mantenida durante migración
  - [x] Re-exports funcionando correctamente
  - [x] 40 tests ejecutándose exitosamente

### 2.3 Onboarding Bounded Context ✅ COMPLETADO
- [x] **Onboarding Domain (`lib/onboarding/domain/`)** ✅
  - [x] Crear `lib/onboarding/domain/interfaces/`
    - [x] Migrar `IProfileService` desde `lib/core/interfaces/`
    - [x] Definir puerto para generación de perfiles y biografías
  - [x] Crear barrel export `domain.dart` funcional

- [x] **Onboarding Infrastructure (`lib/onboarding/infrastructure/`)** ✅
  - [x] Migrar `lib/services/adapters/profile_adapter.dart` → `lib/onboarding/infrastructure/adapters/`
  - [x] Integrar con `runtime_factory` para inyección de dependencias
  - [x] Configurar adaptador con AIService correcto según modelo
  - [x] Crear barrel export `infrastructure.dart` funcional

- [x] **Onboarding Application (`lib/onboarding/application/`)** ✅
  - [x] Migrar `lib/providers/onboarding_provider.dart` → `lib/onboarding/application/providers/`
  - [x] Actualizar imports a package: paths
  - [x] Integrar con ProfileAdapter usando inyección de dependencias
  - [x] Crear barrel export `application.dart` funcional

- [x] **Onboarding Presentation (`lib/onboarding/presentation/`)** ✅
  - [x] Migrar `lib/screens/onboarding_screen.dart` → `lib/onboarding/presentation/screens/`
  - [x] Actualizar imports para usar nueva estructura
  - [x] Crear barrel export `presentation.dart` funcional

- [x] **Onboarding Backward Compatibility** ✅
  - [x] Crear re-export en `lib/providers/onboarding_provider.dart`
  - [x] Crear re-export en `lib/screens/onboarding_screen.dart`
  - [x] Verificar compatibilidad total con imports existentes

- [x] **Onboarding Testing** ✅
  - [x] Todos los tests existentes (40/40) siguen pasando
  - [x] 0 tests requirieron modificación
  - [x] Funcionalidad 100% preservada durante migración
  - [x] Re-exports funcionando correctamente

### 2.4 Voice/Calls Bounded Context
- [x] **Voice Domain (`lib/voice/domain/`)** ✅
  - [x] Crear modelos de dominio para llamadas: `VoiceCall`, `VoiceMessage`, `VoiceProvider`
  - [x] Interfaces para STT/TTS/Realtime: `IVoiceCallRepository`, `IVoiceSttService`, `IVoiceTtsService`, `IVoiceAiService`, `IRealtimeVoiceClient`
  - [x] Servicios de orquestación de llamadas: `VoiceCallValidationService`, `VoiceCallOrchestrationService`
  - [x] Barrel export `domain.dart` funcional

- [x] **Voice Infrastructure (`lib/voice/infrastructure/`)** ✅
  - [x] Migrar clientes realtime:
    - [x] `lib/services/openai_realtime_client.dart` → `OpenAIRealtimeVoiceClient` (adaptado a interface)
    - [x] `lib/services/gemini_realtime_client.dart` → `GeminiRealtimeVoiceClient` (adaptado a interface)
  - [x] Migrar adaptadores STT/TTS:
    - [x] Crear `VoiceSttAdapter`, `VoiceTtsAdapter`, `VoiceAiAdapter` (bridge pattern)
  - [x] Repositorios: `LocalVoiceCallRepository` con SharedPreferences
  - [x] Barrel export `infrastructure.dart` funcional

- [x] **Voice Application (`lib/voice/application/`)** ✅
  - [x] Casos de uso de llamadas de voz:
    - [x] `StartVoiceCallUseCase` - Iniciar llamadas con configuración
    - [x] `EndVoiceCallUseCase` - Finalizar llamadas con cleanup
    - [x] `ProcessUserAudioUseCase` - Procesar audio del usuario
    - [x] `ProcessAssistantResponseUseCase` - Procesar respuestas de IA
    - [x] `GetVoiceCallHistoryUseCase` - Obtener historial de llamadas
    - [x] `ManageVoiceCallConfigUseCase` - Gestionar configuración
  - [x] Barrel export `application.dart` funcional

- [x] **Voice Presentation (`lib/voice/presentation/`)** ✅
  - [x] Migrar `lib/widgets/voice_call_chat.dart` → `lib/voice/presentation/screens/voice_call_screen.dart` (correcta clasificación arquitectural)
  - [x] Migrar widgets de soporte:
    - [x] `voice_call_painters.dart` → `lib/voice/presentation/widgets/`
    - [x] `cyberpunk_subtitle.dart` → `lib/voice/presentation/widgets/`
  - [x] Actualizar imports a relative paths dentro del bounded context
  - [x] Crear barrel exports `screens.dart`, `widgets.dart`, `presentation.dart`

- [x] **Voice Backward Compatibility** ✅
  - [x] Crear re-export en `lib/widgets/voice_call_chat.dart` → Voice screen
  - [x] Compatibilidad files creados para widgets migrados
  - [x] Verificar imports existentes siguen funcionando
  - [x] Referencias en `chat_screen.dart` actualizadas correctamente

- [x] **Voice Testing** ✅
  - [x] Todos los tests existentes (40/40) siguen pasando
  - [x] 0 errores de análisis estático
  - [x] Funcionalidad 100% preservada durante migración
  - [x] Re-exports funcionando correctamente
### 2.5 Shared/Core refinamiento
- [x] **Shared components (`lib/shared/`)** ✅
  - [x] Migrar `lib/constants/` → `lib/shared/constants/` ✅
  - [x] Migrar `lib/utils/` → `lib/shared/utils/` ✅
  - [x] Crear estructura base para widgets compartidos → `lib/shared/widgets/` ✅
  - [x] Crear barrel exports para acceso limpio ✅
  - [x] Crear re-exports para backward compatibility ✅

- [ ] **Core cleanup (`lib/core/`)** 🔄
  - [ ] Mantener solo infraestructura compartida
  - [ ] Interfaces que sean verdaderamente compartidas
  - [ ] Modelos de dominio compartidos entre contexts

---

## ⏳ FASE 3: REFINAMIENTO Y OPTIMIZACIÓN FINAL

### 3.1 Revisión de interfaces y contratos
- [ ] **Audit de puertos (interfaces)**
  - [ ] Verificar que todos los ports están en el lugar correcto
  - [ ] Eliminar interfaces duplicadas
  - [ ] Asegurar que adapters implementan ports correctamente

- [ ] **Dependency direction audit**
  - [ ] Verificar que dominio no depende de infraestructura
  - [ ] Verificar que application coordina domain + infrastructure
  - [ ] Verificar que presentation solo usa application layer

### 3.2 Testing strategy completitud
- [ ] **Tests por bounded context**
  - [ ] Unit tests de dominio (aislados, sin I/O)
  - [ ] Integration tests por context
  - [ ] Contract tests entre contexts
  - [ ] End-to-end tests críticos

- [ ] **Test coverage analysis**
  - [ ] Verificar >90% coverage en domain layers
  - [ ] Verificar >80% coverage en application layers
  - [ ] Smoke tests para infrastructure layers

### 3.3 Performance y optimización
- [ ] **DI container optimization**
  - [ ] Lazy loading donde sea apropiado
  - [ ] Singleton lifecycle correctamente gestionado
  - [ ] Memory leaks audit

- [ ] **Cross-context communication**
  - [ ] Event-driven communication donde sea necesario
  - [ ] Shared kernel bien definido y minimal
  - [ ] Anti-corruption layers si es necesario

### 3.4 Documentation y guidelines
- [ ] **Architecture Decision Records (ADRs)**
  - [ ] Documentar decisiones de bounded contexts
  - [ ] Documentar patterns utilizados
  - [ ] Guidelines para nuevos desarrolladores

- [ ] **Code examples y templates**
  - [ ] Template para añadir nuevas features
  - [ ] Examples de testing patterns
  - [ ] Guía de contribution

---

## 📊 ESTADO ACTUAL DETALLADO

### ✅ Completado (Fases 1-2 casi completa)
- **Infraestructura básica:** Config, DI, RuntimeFactory funcionando ✅
- **Quality gates:** CI/CD, tests de regresión, análisis estático ✅
- **Chat Bounded Context:** Migración completa con DDD + Hexagonal ✅
- **Onboarding Bounded Context:** Migración completa con DDD + Hexagonal ✅
- **Voice Bounded Context:** Migración completa con DDD + Hexagonal ✅
- **Shared Kernel:** Constants + Utils migrados, estructura preparada ✅
- **Foundation sólida:** 40/40 tests passing, flutter analyze limpio ✅
- **Legacy cleanup:** 8 archivos legacy eliminados, deprecaciones resueltas ✅

### 🔄 En Progreso (Fase 2 finalizando)  
- **Último objetivo:** Core cleanup final y refinamiento de interfaces
- **Estructura actual:** 3.5 de 4 bounded contexts completados (90% progreso general)
- **Testing:** 40/40 tests funcionando perfectamente, sin regresiones

### ⏳ Pendiente (Fases 2-3)
- **Reorganización completa:** Mover archivos a estructura DDD completa
- **Context isolation:** Asegurar boundaries claros entre contexts  
- **Advanced testing:** Test strategy completa por layers y contexts
- **Documentation:** ADRs y guidelines para el equipo

---

## 🚀 PLAN DE EJECUCIÓN

### Próximo sprint (Fase 2 final + Fase 3)
1. **Core Infrastructure Cleanup** (estimado: 1-2 días)
   - Revisar y limpiar lib/core/ para mantener solo shared infrastructure
   - Consolidar interfaces realmente compartidas
   - Verificar que domain models estén en el lugar correcto

2. **Final Testing & Documentation** (estimado: 1-2 días)
   - Verificar cobertura de tests >90% en domain layers
   - Crear ADRs (Architecture Decision Records)
   - Guidelines para el equipo
   - Verificar funcionamiento end-to-end completo

3. **Performance & Optimization Review** (estimado: 1-2 días)
   - DI container optimization review
   - Memory leaks audit
   - Cross-context communication patterns review

### Criterios de éxito por fase
- **Post Fase 2:** Estructura clara por contexts, tests pasando, código funcional
- **Post Fase 3:** >90% test coverage en domain, documentación completa, guidelines establecidas

---

## 🧹 ESTRATEGIA DE LIMPIEZA DE ARCHIVOS ANTIGUOS

### Fase A: Re-exports Temporales (ACTUAL)
**Estado:** Archivos antiguos como re-exports → archivos nuevos

**Ejemplo actual (Chat):**
```dart
// lib/screens/chat_screen.dart (re-export temporal)
export '../chat/presentation/screens/chat_screen.dart';
```

**Cuándo mantener:** Durante toda la Fase 2 de migración (2-3 bounded contexts más)

### Fase B: Deprecación Gradual 
**Cuándo:** Después de completar TODOS los bounded contexts (Onboarding, Voice, Core)

**Proceso:**
1. **Marcar como deprecated** (con `@deprecated` y warnings):
   ```dart
   // lib/screens/chat_screen.dart
   @deprecated('Use import "package:ai_chan/chat.dart" instead')
   export '../chat/presentation/screens/chat_screen.dart';
   ```

2. **Actualizar imports progresivamente** en el código:
   ```dart
   // Cambiar de:
   import 'package:ai_chan/screens/chat_screen.dart';
   
   // A:
   import 'package:ai_chan/chat.dart';
   ```

3. **Período de gracia**: 1-2 sprints para actualizar imports

### Fase C: Eliminación Segura
**Cuándo:** Solo después de verificar que no hay imports directos

**Archivos a eliminar eventualmente:**
```
lib/screens/chat_screen.dart          → eliminar (re-export)
lib/widgets/chat_bubble.dart          → eliminar (re-export) 
lib/widgets/message_input.dart        → eliminar (re-export)
lib/widgets/tts_configuration_dialog.dart → eliminar (re-export)
lib/providers/chat_provider.dart      → eliminar (re-export)
```

**Verificación antes de eliminar:**
```bash
# Buscar imports directos que aún usen rutas antiguas
grep -r "screens/chat_screen" lib/ test/ --exclude="*.md"
grep -r "widgets/chat_bubble" lib/ test/ --exclude="*.md"  
grep -r "providers/chat_provider" lib/ test/ --exclude="*.md"

# Si hay 0 resultados → SEGURO ELIMINAR
```

---

## ⏰ CRONOGRAMA DE LIMPIEZA

### Inmediato (Ahora):
- ✅ **Mantener re-exports** - Compatibilidad total
- ✅ **0 breaking changes** - Sistema estable

### Fase 2 Completa (~2-3 semanas):
- 🔄 **Mantener re-exports** - Hasta completar todos los contexts
- ⏳ **Actualizar imports internos** - Usar barrel exports

### Post-Migración (~1 mes):
- 📝 **Deprecar re-exports** - Warnings pero funcional
- 🔍 **Audit de imports** - Encontrar usos antiguos
- 🧹 **Limpieza gradual** - Eliminar archivos sin romper nada

### Final (2-3 meses):
- ❌ **Eliminar archivos antiguos** - Solo re-exports sin uso
- ✅ **Arquitectura limpia** - Solo estructura DDD

---

## 🛡️ REGLAS DE SEGURIDAD

1. **NUNCA eliminar** si hay imports activos
2. **SIEMPRE verificar** con búsqueda de texto completa
3. **MANTENER tests** funcionando en todo momento
4. **DOCUMENTAR cambios** para el equipo

La ventaja de usar re-exports es que podemos migrar la arquitectura **SIN PRISA** y limpiar cuando sea 100% seguro.

---

## 🔍 COMANDOS DE VERIFICACIÓN

```bash
# Verificar estado actual
flutter analyze
flutter test

# Verificar estructura after migration
find lib -name "*.dart" | head -20
flutter test --coverage

# Verificar dependencies
flutter pub deps --style=compact

# Verificar que no hay instanciaciones directas
grep -r "OpenAIService(" lib/ --exclude-dir=core
grep -r "GeminiService(" lib/ --exclude-dir=core
```

---

**Estado:** FASE 1 ✅ COMPLETADA | FASE 2 🔄 EN PREPARACIÓN | FASE 3 ⏳ PENDIENTE

Si quieres que aplique el sub-batch ampliado ahora, dime “OK, aplica el sub-batch ampliado”.

