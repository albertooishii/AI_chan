# 📋 DEUDAS TÉCNICAS Y PLAN DE MIGRACIÓN DDD

## 🚨 ESTADO ACTUAL (5 septiembre 2025)

### ✅ COMPLETADO
- **Domain Layer:** ✅ 100% LIMPIO - Sin dependencias externas
- **Application Layer:** ✅ 90% LIMPIO - Solo ChatProvider pendiente de eliminación
  - ✅ TtsService refactorizado para usar IFileService
  - ✅ ImportExportOnboardingUseCase refactorizado para usar IFileService
  
### 🔧 INTERFACES DDD CREADAS
- ✅ `IFileService` - Interface para operaciones de archivo
- ✅ `FileService` - Implementación en Infrastructure
- ✅ `IChatRepository` - Interface del repositorio de chat
- ✅ `IPromptBuilderService` - Interface para construcción de prompts

## ⚠️ DEUDAS TÉCNICAS DOCUMENTADAS

### 1. Application Layer - ChatProvider Legacy (ALTA PRIORIDAD)
**Archivo:** `lib/chat/application/providers/chat_provider.dart`
**Problema:** Usa `dart:io` directamente, viola DDD
**Solución:** ELIMINAR completamente y migrar a ChatController + ChatApplicationService
**Fecha límite:** Sprint 1 (2 semanas)
**Riesgo:** Alto - Es el núcleo de la funcionalidad de chat

### 2. Presentation Layer - File Operations (MEDIA PRIORIDAD)
**Archivos afectados:**
- `lib/chat/presentation/widgets/message_input.dart`
- `lib/chat/presentation/widgets/chat_bubble.dart` 
- `lib/chat/presentation/widgets/tts_configuration_dialog.dart`
- `lib/chat/presentation/widgets/audio_message_player.dart`
- `lib/chat/presentation/widgets/expandable_image_dialog.dart`
- `lib/chat/presentation/screens/gallery_screen.dart`
- `lib/chat/presentation/screens/chat_screen.dart`
- `lib/onboarding/presentation/screens/onboarding_mode_selector.dart`

**Problema:** Acceso directo a `File()` desde widgets de UI
**Solución:** Mover operaciones de archivo a servicios de Application/Infrastructure
**Fecha límite:** Sprint 2 (4 semanas)
**Riesgo:** Medio - Funcionalidad funciona pero viola arquitectura

### 3. Tests Legacy - Cleanup (BAJA PRIORIDAD)
**Archivos identificados para eliminar:**
- `test/chat/avatar_persist_utils_test.dart` - Depende de ChatProvider obsoleto
- `test/chat/profile_persist_utils_test.dart` - Depende de ChatProvider obsoleto  
- `test/chat/local_chat_repository_test.dart` - Posible redundancia con DDD
- `test/chat/send_message_usecase_ai_service_test.dart` - Evaluar si sobra

**Utilidades obsoletas que dependen de ChatProvider:**
- `lib/chat/application/utils/avatar_persist_utils.dart` - Migrar a ChatApplicationService
- `lib/chat/application/utils/profile_persist_utils.dart` - Migrar a ChatApplicationService

**Problema:** Tests que dependen de implementaciones obsoletas
**Solución:** Revisar y eliminar tests redundantes, migrar funcionalidad a DDD
**Fecha límite:** Sprint 3 (6 semanas)
**Riesgo:** Bajo - No afecta funcionalidad

## 🎯 PLAN DE MIGRACIÓN POR FASES

### FASE 1: Completar DDD Core (2 semanas)
- [ ] Eliminar ChatProvider completamente
- [ ] Migrar todos los usos a ChatController + ChatApplicationService
- [ ] Crear tests robustos para nueva arquitectura DDD
- [ ] Application Layer 100% limpio

### FASE 2: Infrastructure Services (4 semanas)  
- [ ] Crear IImageService para operaciones de imagen
- [ ] Crear IAudioService para operaciones de audio
- [ ] Migrar widgets de Presentation para usar servicios
- [ ] Presentation Layer 100% limpio

### FASE 3: Test Cleanup (6 semanas)
- [ ] Revisar todos los tests de arquitectura legacy
- [ ] Eliminar tests redundantes que sobran
- [ ] Validar que no se rompe funcionalidad
- [ ] Suite de tests optimizada

## 🔍 AUDITORÍA DE TESTS DE ARQUITECTURA

### Tests a ELIMINAR (redundantes con DDD)
```bash
# Ya eliminados en esta sesión
test/chat/chat_provider_test.dart ❌ ELIMINADO
test/chat/chat_provider_adapter_test.dart ❌ ELIMINADO  
test/chat/chat_provider_avatar_test.dart ❌ ELIMINADO
test/integration/app_full_flow_test.dart ❌ ELIMINADO
test/onboarding/persistence_test.dart ❌ ELIMINADO
test/shared/auto_backup_simple_test.dart ❌ ELIMINADO

# Por revisar
test/architecture/ddd_layer_test.dart ❌ ELIMINADO (superficial)
test/architecture/presentation_layer_test.dart ❌ ELIMINADO (superficial)
```

### Tests a CONSERVAR (críticos)
```bash
test/architecture/clean_ddd_architecture_test.dart ✅ PRINCIPAL
test/core/services/ ✅ Tests de servicios específicos
test/shared/domain/ ✅ Tests de dominio puro  
test/*/use_cases/ ✅ Tests de casos de uso
```

## 🚦 CONFIGURACIÓN TEMPORAL

Para no bloquear desarrollo mientras migramos, aplicamos estas reglas temporales:

1. **Domain Layer:** ❌ CERO TOLERANCIA - Debe ser 100% puro
2. **Application Layer:** ⚠️ Solo ChatProvider permitido temporalmente
3. **Presentation Layer:** ⚠️ File() operations permitidas temporalmente
4. **Infrastructure Layer:** ✅ Puede usar cualquier dependencia externa

## 📊 MÉTRICAS DE PROGRESO

| Capa | Estado Actual | Meta Sprint 1 | Meta Sprint 2 | Meta Final |
|------|---------------|---------------|---------------|------------|
| Domain | ✅ 100% | ✅ 100% | ✅ 100% | ✅ 100% |
| Application | 🔶 90% | ✅ 100% | ✅ 100% | ✅ 100% |
| Infrastructure | ✅ 100% | ✅ 100% | ✅ 100% | ✅ 100% |
| Presentation | 🔴 0% | 🔴 0% | ✅ 100% | ✅ 100% |

## ⚡ ACCIONES INMEDIATAS

1. ✅ Aplicar configuración temporal en tests DDD
2. ✅ Documentar todas las deudas técnicas  
3. ✅ Identificar tests legacy para eliminar
4. 🔄 Continuar con migración gradual sin romper funcionalidad

---
> **NOTA:** Este documento debe actualizarse cada vez que se resuelva una deuda técnica o se identifique una nueva.
