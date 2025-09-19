# 🚀 PLAN DE ACCIÓN ACTUALIZADO - DATOS DEL TEST GENÉRICO

**Fecha**: 19 de septiembre de 2025  
**Fuente**: `test/architecture/import_redundancy_test.dart` ejecutado  
**Total violations detectadas**: 408 (240+94+74)

## 🎯 NUEVA PRIORIZACIÓN BASADA EN DATOS REALES

### 🚨 FASE 1: CRITICAL FIXES (74 violaciones críticas)
**Tiempo estimado**: 12-15 horas  
**Impacto**: Rompen Clean Architecture

#### 1.1 Cross-Context Dependencies (73 violaciones)

**onboarding → chat (4 archivos detectados)**:
```bash
lib/onboarding/presentation/controllers/onboarding_lifecycle_controller.dart:5
lib/onboarding/presentation/screens/onboarding_mode_selector.dart:17
lib/onboarding/presentation/screens/onboarding_screen.dart:15
lib/onboarding/infrastructure/adapters/chat_export_service_adapter.dart:2
```

**Plan específico**:
1. **Crear SharedNavigationService** (3-4h)
   ```dart
   // lib/shared/application/services/navigation_service.dart
   abstract class INavigationService {
     Future<void> navigateToChat();
     Future<void> navigateToVoice();
   }
   ```

2. **Refactorizar onboarding controllers** (4-5h)
   - Inyectar INavigationService
   - Eliminar imports directos de chat

3. **Crear SharedChatExportService** (2-3h)
   - Mover lógica de chat_export_service_adapter
   - Implementar en shared/infrastructure

**chat → voice (1 archivo detectado)**:
```bash
lib/chat/presentation/screens/chat_screen.dart:20
```

**Plan específico**:
1. **Implementar AppRouter** (3-4h)
   ```dart
   // lib/shared/infrastructure/routing/app_router.dart
   class AppRouter {
     static const String voiceRoute = '/voice';
     static const String chatRoute = '/chat';
   }
   ```

#### 1.2 Screen Cross-Imports (1 violación)
**Tiempo estimado**: 2-3 horas

```dart
// ANTES:
import 'package:ai_chan/voice/presentation/screens/voice_screen.dart';

// DESPUÉS:
// Usar AppRouter.pushNamed('/voice')
```

### ⚠️ FASE 2: ARCHITECTURAL VIOLATIONS (334 violaciones)
**Tiempo estimado**: 15-20 horas

#### 2.1 Direct shared.dart Imports (240 violaciones)
**Patrón detectado**: Import directo de `shared/domain/models/index.dart`

**Archivos principales afectados**:
```bash
lib/chat/presentation/controllers/_chat_call_controller.dart
lib/chat/presentation/controllers/_chat_data_controller.dart
lib/chat/presentation/controllers/_chat_audio_controller.dart
lib/chat/presentation/controllers/_chat_message_controller.dart
lib/chat/presentation/controllers/chat_controller.dart
# ... +235 archivos más
```

**Plan de masa**:
1. **Script automático de refactoring** (4-5h)
   ```bash
   # Crear script para reemplazar en masa:
   find lib/ -name "*.dart" -exec sed -i "s|shared/domain/models/index.dart|shared.dart|g" {} \;
   ```

2. **Validación manual** (3-4h)
   - Verificar que todos los imports funcionen
   - Verificar exports en shared.dart

#### 2.2 Presentation → Infrastructure (94 violaciones)
**Archivo principal**: `tts_configuration_dialog.dart` (5 imports directos)

**Violaciones típicas detectadas**:
```dart
import 'package:ai_chan/shared/infrastructure/cache/cache_service.dart';
import 'package:ai_chan/shared/infrastructure/di/di.dart';
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';
import 'package:ai_chan/shared/infrastructure/utils/dialog_utils.dart';
import 'package:ai_chan/shared/infrastructure/utils/prefs_utils.dart';
```

**Plan específico**:
1. **Verificar exports en shared.dart** (2h)
   - Asegurar que todos los utils estén exportados

2. **Refactoring masivo** (8-10h)
   ```bash
   # Reemplazar todos los imports de infrastructure con shared.dart
   find lib/ -name "*.dart" -exec sed -i "s|shared/infrastructure/|shared.dart // |g" {} \;
   ```

### 🎭 FASE 3: INTERFACE CONSOLIDATION (8 duplicadas)
**Tiempo estimado**: 8-12 horas

#### 3.1 Audio Services Duplicates (5 interfaces)

**ITextToSpeechService duplicada**:
```bash
lib/voice/domain/interfaces/voice_services.dart
lib/shared/domain/interfaces/cross_context_interfaces.dart
```

**Plan consolidación**:
1. **Mantener versión en shared/** (1h)
2. **Deprecar versión en voice/** (1h)
3. **Migrar referencias** (2-3h)

**Misma estrategia para**:
- ISpeechToTextService
- IAudioRecorderService  
- ITtsService
- ISttService

### 📊 FASE 4: REDUNDANCY OPTIMIZATION (664 redundancias)
**Tiempo estimado**: 20-25 horas

#### 4.1 AI Providers Redundancy (201 ocurrencias)
**Plan**: Consolidar imports de ai_providers en shared.dart

#### 4.2 Cross-Context Imports (162 ocurrencias)  
**Plan**: Mover utilities comunes a shared/

#### 4.3 Infrastructure Utils (126 ocurrencias)
**Plan**: Optimizar exports en shared.dart

## 📋 CRONOGRAMA IMPLEMENTACIÓN

### Sprint 1 (Week 1): CRITICAL FIXES
- [ ] Día 1-2: Cross-context dependencies (12h)
- [ ] Día 3: Screen cross-imports (3h)
- [ ] **Meta**: 0 violaciones críticas

### Sprint 2 (Week 2): ARCHITECTURAL CLEANUP  
- [ ] Día 1-2: Direct shared.dart imports (8h)
- [ ] Día 3-4: Presentation→Infrastructure (12h)
- [ ] **Meta**: Clean architectural layers

### Sprint 3 (Week 3): CONSOLIDATION
- [ ] Día 1-2: Interface deduplication (10h)
- [ ] Día 3-5: Redundancy optimization (15h)
- [ ] **Meta**: Optimized codebase

## 🎯 SUCCESS METRICS

| Métrica | Actual | Meta Fase 1 | Meta Final |
|---------|--------|-------------|------------|
| **Cross-context violations** | 74 | 0 | 0 |
| **Direct imports** | 240 | 240 | 0 |
| **Presentation→Infrastructure** | 94 | 94 | 0 |
| **Interface duplicates** | 8 | 8 | 0 |
| **Total redundancies** | 664 | 664 | <100 |

## 🚀 LISTO PARA IMPLEMENTAR

**Próximo comando**:
```bash
# Ejecutar test para baseline
dart test test/architecture/import_redundancy_test.dart
```

**Primer refactoring**:
1. Crear SharedNavigationService
2. Refactorizar onboarding→chat dependencies  
3. Implementar AppRouter

---

*Plan generado desde datos reales del test genérico de arquitectura*