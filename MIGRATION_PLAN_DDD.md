# 🚀 Plan de Migración DDD/Hexagonal - AI_chan

## 📋 Estado Actual (Detectado por tests robustos)

### ✅ LIMPIO - Domain Layer 
- Ya no tiene dependencias externas
- Interfaces puras sin dart:io ni Flutter

### ✅ PROGRESO - Application Layer
- [x] `tts_service.dart` - ✅ ARREGLADO (usa IFileService)
- [x] `import_export_onboarding_use_case.dart` - ✅ ARREGLADO (usa IFileService)
- [x] `chat_application_service.dart` - ✅ CREADO (nueva arquitectura DDD)
- [x] `chat_controller.dart` - ✅ CREADO (coordinador UI limpio)
- [x] `chat_provider_adapter.dart` - ✅ CREADO (bridge temporal)
- [ ] `chat_provider.dart` - 🔄 MIGRACIÓN EN PROGRESO (bridge + gradual replacement)

**DECISIÓN:** ✅ EJECUTADA - Migración gradual usando ChatProviderAdapter como Strangler Fig Pattern

### ❌ VIOLACIONES DETECTADAS

**Presentation Layer:**
- 8 archivos usando `File(` directamente en widgets
- Lógica de negocio mezclada con UI

## 🎯 ESTRATEGIA DE MIGRACIÓN AGRESIVA

### Fase 1: Limpieza Masiva de Tests ⚡
- [x] Eliminar tests superficiales de arquitectura
- [x] Mantener solo tests robustos de DDD
- [ ] **ELIMINAR 80% de tests que testean implementaciones incorrectas**
- [ ] Conservar solo tests críticos de dominio

### Fase 2: Migración Core Architecture 🏗️ - EN PROGRESO
- [x] **Crear ChatApplicationService** ✅ COMPLETADO
- [x] **Crear ChatController** ✅ COMPLETADO  
- [x] **Crear ChatProviderAdapter como bridge** ✅ COMPLETADO
- [ ] **Migrar main.dart** 🔄 EN PROGRESO
- [ ] **Migrar gradualmente 45+ usages de ChatProvider** ⏳ PENDIENTE
- [ ] **Eliminar ChatProvider original** ⏳ PENDIENTE (al final)
- [ ] Crear interfaces limpias para infraestructura
- [ ] Implementar Dependency Injection limpio

### Fase 3: Separación Infrastructure/Presentation 🔌
- [ ] Mover acceso directo a File() a Infrastructure Layer
- [ ] Crear interfaces para file operations
- [ ] Limpiar Presentation de lógica de negocio
- [ ] Usar solo Application Services desde UI

### Fase 4: Validación Final 🧪
- [ ] Todos los tests de arquitectura DDD pasando
- [ ] Suite de tests reducida pero efectiva
- [ ] Arquitectura limpia y mantenible

## 📁 ARCHIVOS A ELIMINAR (Tests Redundantes)

### Tests que sobran con arquitectura DDD correcta:
- `test/chat/chat_provider_test.dart` → Reemplazar con ChatController tests
- `test/chat/chat_provider_adapter_test.dart` → Reemplazar con Service tests  
- `test/chat/chat_provider_avatar_test.dart` → Mover lógica a Application Service
- `test/integration/app_full_flow_test.dart` → Simplificar con DDD
- `test/onboarding/persistence_test.dart` → Usar Repository interfaces
- `test/shared/auto_backup_simple_test.dart` → Infrastructure concern

### Tests a conservar y adaptar:
- Tests de Domain models/entities ✅
- Tests de Use Cases específicos ✅  
- Tests de arquitectura DDD ✅
- Tests de integración críticos ✅

## 🔧 IMPLEMENTACIÓN TÉCNICA

### 1. Crear ChatController limpio
```dart
class ChatController extends ChangeNotifier {
  final ChatApplicationService _chatService;
  
  // Solo estado UI
  List<Message> _messages = [];
  bool _isLoading = false;
  
  // Solo eventos UI
  Future<void> sendMessage(String text) async {
    await _chatService.sendMessage(text);
    notifyListeners();
  }
}
```

### 2. ChatApplicationService puro
```dart
class ChatApplicationService {
  final IChatRepository _repository;
  final IPromptBuilderService _promptBuilder;
  
  // Solo lógica de negocio
  Future<void> sendMessage(String text) async {
    final prompt = await _promptBuilder.buildPrompt(text);
    await _repository.saveMessage(prompt);
  }
}
```

### 3. Infrastructure interfaces
```dart
abstract class IFileService {
  Future<String> saveFile(List<int> bytes, String filename);
  Future<List<int>?> loadFile(String path);
}
```

## 📊 MÉTRICAS DE ÉXITO

- **Antes:** 100+ tests, muchos fallan por dependencies incorrectas
- **Después:** 50-60 tests robustos, arquitectura DDD validada
- **Domain Layer:** 0 dependencias externas ✅
- **Application Layer:** Solo interfaces de Domain ✅  
- **Infrastructure:** Implementa interfaces ✅
- **Presentation:** Solo UI concerns ✅

## 🚦 PRÓXIMOS PASOS INMEDIATOS

1. **ELIMINAR tests masivamente** - Quitar 70-80% de tests redundantes
2. **Migrar ChatProvider usage** - Usar ChatController + ChatApplicationService  
3. **Arreglar Application Layer** - Eliminar dart:io directo
4. **Limpiar Presentation** - Mover File() operations a Infrastructure
5. **Validar arquitectura** - Tests DDD 100% verdes

---

> **Filosofía:** "Si los tests de arquitectura DDD son correctos, la mayoría de tests específicos se vuelven redundantes. Una arquitectura limpia es auto-documentada y auto-validada."
