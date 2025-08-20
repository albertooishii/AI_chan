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
4. **Core** - Shared kernel e infraestructura compartida

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

### 2.2 Chat Bounded Context
- [ ] **Chat Domain (`lib/chat/domain/`)**
  - [ ] Crear `lib/chat/domain/models/`
    - [ ] Migrar `lib/models/chat_message.dart`
    - [ ] Migrar `lib/models/chat_event.dart` 
    - [ ] Crear `chat_conversation.dart` aggregate
  - [ ] Crear `lib/chat/domain/interfaces/`
    - [ ] Migrar `IChatRepository` desde `lib/core/interfaces/`
    - [ ] Migrar `IChatResponseService` desde `lib/core/interfaces/`
    - [ ] Añadir `IChatService` para casos de uso
  - [ ] Crear `lib/chat/domain/services/`
    - [ ] Migrar `memory_summary_service.dart`
    - [ ] Crear servicios de validación de chat

- [ ] **Chat Infrastructure (`lib/chat/infrastructure/`)**
  - [ ] Crear `lib/chat/infrastructure/repositories/`
    - [ ] Migrar `lib/chat/repositories/local_chat_repository.dart`
  - [ ] Crear `lib/chat/infrastructure/adapters/`
    - [ ] Migrar `lib/chat/services/adapters/ai_chat_response_adapter.dart`
    - [ ] Migrar `lib/services/ai_chat_response_service.dart`

- [ ] **Chat Application (`lib/chat/application/`)**
  - [ ] Migrar `lib/providers/chat_provider.dart` → `lib/chat/application/chat_provider.dart`
  - [ ] Crear casos de uso explícitos:
    - [ ] `send_message_use_case.dart`
    - [ ] `load_chat_history_use_case.dart`
    - [ ] `export_chat_use_case.dart`
    - [ ] `import_chat_use_case.dart`

- [ ] **Chat Presentation (`lib/chat/presentation/`)**
  - [ ] Migrar `lib/screens/chat_screen.dart` → `lib/chat/presentation/screens/`
  - [ ] Migrar widgets específicos de chat:
    - [ ] `lib/widgets/chat_bubble.dart` → `lib/chat/presentation/widgets/`
    - [ ] `lib/widgets/message_input.dart` → `lib/chat/presentation/widgets/`
    - [ ] `lib/widgets/tts_configuration_dialog.dart` → `lib/chat/presentation/widgets/`

- [ ] **Chat Testing**
  - [ ] Migrar tests existentes a nueva estructura:
    - [ ] `test/chat/` → mantener estructura por capas
    - [ ] Añadir tests de dominio puros (sin dependencias externas)
    - [ ] Tests de casos de uso con mocks
    - [ ] Tests de integración por bounded context

### 2.3 Onboarding Bounded Context
- [ ] **Onboarding Domain (`lib/onboarding/domain/`)**
  - [ ] Crear `lib/onboarding/domain/models/`
    - [ ] Migrar `lib/models/ai_chan_profile.dart`
    - [ ] Migrar `lib/models/ai_image.dart`
    - [ ] Crear `user_preferences.dart` value object
  - [ ] Crear `lib/onboarding/domain/interfaces/`
    - [ ] Migrar `IProfileService` desde `lib/core/interfaces/`
    - [ ] Añadir `IUserOnboardingService`
    - [ ] Añadir `IAppearanceGenerationService`
  - [ ] Crear `lib/onboarding/domain/services/`
    - [ ] Migrar generadores de biografía e imagen
    - [ ] Servicios de validación de perfil

- [ ] **Onboarding Infrastructure (`lib/onboarding/infrastructure/`)**
  - [ ] Migrar `lib/services/adapters/profile_adapter.dart` → `lib/onboarding/infrastructure/adapters/`
  - [ ] Migrar servicios de persistencia de perfil
  - [ ] Adaptadores para generación de imágenes

- [ ] **Onboarding Application (`lib/onboarding/application/`)**
  - [ ] Migrar `lib/providers/onboarding_provider.dart`
  - [ ] Crear casos de uso:
    - [ ] `generate_profile_use_case.dart`
    - [ ] `save_profile_use_case.dart`
    - [ ] `load_profile_use_case.dart`

- [ ] **Onboarding Presentation (`lib/onboarding/presentation/`)**
  - [ ] Migrar `lib/screens/onboarding_screen.dart`
  - [ ] Migrar widgets específicos de onboarding

- [ ] **Onboarding Testing**
  - [ ] Reorganizar `test/onboarding/` por capas DDD
  - [ ] Tests de dominio puros
  - [ ] Tests de casos de uso

### 2.4 Voice/Calls Bounded Context
- [ ] **Voice Domain (`lib/voice/domain/`)**
  - [ ] Crear modelos de dominio para llamadas
  - [ ] Interfaces para STT/TTS/Realtime
  - [ ] Servicios de orquestación de llamadas

- [ ] **Voice Infrastructure (`lib/voice/infrastructure/`)**
  - [ ] Migrar clientes realtime:
    - [ ] `lib/services/openai_realtime_client.dart`
    - [ ] `lib/services/gemini_realtime_client.dart`
  - [ ] Migrar adaptadores STT/TTS:
    - [ ] `lib/services/adapters/google_stt_adapter.dart`
    - [ ] `lib/services/adapters/google_tts_adapter.dart`
    - [ ] `lib/services/adapters/default_tts_service.dart`

- [ ] **Voice Application (`lib/voice/application/`)**
  - [ ] Casos de uso de llamadas de voz
  - [ ] Providers/controllers para UI de voz

- [ ] **Voice Presentation (`lib/voice/presentation/`)**
  - [ ] Migrar `lib/widgets/voice_call_chat.dart`
  - [ ] UI específica de llamadas

- [ ] **Voice Testing**
  - [ ] Reorganizar `test/calls/` según nueva estructura
  - [ ] Tests de orquestación de voz

### 2.5 Shared/Core refinamiento
- [ ] **Shared components (`lib/shared/`)**
  - [ ] Migrar `lib/constants/` → `lib/shared/constants/`
  - [ ] Migrar `lib/utils/` → `lib/shared/utils/`
  - [ ] Migrar widgets UI generales → `lib/shared/widgets/`

- [ ] **Core cleanup (`lib/core/`)**
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

### ✅ Completado (Fase 1)
- **Infraestructura básica:** Config, DI, RuntimeFactory funcionando
- **Quality gates:** CI/CD, tests de regresión, análisis estático
- **Foundation:** 40/40 tests passing, flutter analyze limpio

### 🔄 En Progreso (Fase 2)  
- **Estructura actual:** Código funcionando pero no organizado por contexts
- **Migración:** Necesaria reorganización de carpetas y archivos
- **Testing:** Tests funcionando pero necesitan reorganización por layers

### ⏳ Pendiente (Fases 2-3)
- **Reorganización completa:** Mover archivos a estructura DDD completa
- **Context isolation:** Asegurar boundaries claros entre contexts  
- **Advanced testing:** Test strategy completa por layers y contexts
- **Documentation:** ADRs y guidelines para el equipo

---

## 🚀 PLAN DE EJECUCIÓN

### Próximo sprint (Fase 2.1)
1. **Chat Context Migration** (estimado: 2-3 días)
   - Crear estructura de carpetas para chat context
   - Migrar modelos y repositorio de chat
   - Actualizar imports y verificar tests

2. **Onboarding Context Migration** (estimado: 2-3 días)
   - Reorganizar lógica de onboarding
   - Separar domain/infrastructure/application/presentation
   - Migrar y reorganizar tests

3. **Voice Context Migration** (estimado: 1-2 días)
   - Aislar lógica de voz y llamadas
   - Migrar clientes realtime y adaptadores
   - Verificar funcionamiento end-to-end

### Criterios de éxito por fase
- **Post Fase 2:** Estructura clara por contexts, tests pasando, código funcional
- **Post Fase 3:** >90% test coverage en domain, documentación completa, guidelines establecidas

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

