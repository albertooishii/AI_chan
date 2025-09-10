# 🎤 Sistema Realtime - Integración con Providers Dinámicos

## 📊 **Estado Actual - Septiembre 2025**

### **🎯 Objetivo**
Unificar el sistema realtime con el sistema de providers dinámicos desacoplado para lograr una arquitectura coherente y 100% configurable.

### **⚖️ Estado Actual**
| Componente | Estado | Descripción |
|------------|--------|-------------|
| **OpenAI Realtime** | ✅ Funcional | Cliente WebSocket estable, pero separado |
| **Provider Integration** | 🟡 Parcial | Usa sistema DI legacy independiente |
| **Dynamic Keys** | ✅ Migrado | Ya usa ApiKeyManager dinámico |
| **Registry Integration** | ❌ Pendiente | No unificado con registry principal |

**🎯 Progreso**: **6.5/10** (Parcialmente Integrado)

## 🏗️ **Arquitectura Actual**

### **Sistema Realtime Existente**
```dart
// lib/call/services/openai_realtime_voice_client.dart
class OpenAIRealtimeVoiceClient extends RealtimeVoiceClient {
  // ✅ YA MIGRADO: Usa ApiKeyManager
  String get _apiKey {
    final key = ApiKeyManager.getNextAvailableKey('openai');
    if (key == null || key.isEmpty) {
      throw Exception('No valid OpenAI API key available. Configure OPENAI_API_KEYS.');
    }
    return key;
  }

  @override
  Future<void> connect() async {
    final uri = Uri.parse('wss://api.openai.com/v1/realtime?model=${_selectedModel}');
    _webSocket = await WebSocket.connect(
      uri.toString(),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'OpenAI-Beta': 'realtime=v1'
      },
    );
  }
}
```

### **Problema: DI Legacy Separado**
```dart
// ❌ PROBLEMA: Sistema DI independiente del registry dinámico
class CallDependencyProvider with ChangeNotifier {
  RealtimeVoiceClient getRealtimeClientForProvider(String providerId) {
    switch (providerId.toLowerCase()) {    // ❌ HARDCODED
      case 'openai':
        return OpenAIRealtimeVoiceClient(); // ❌ SEPARADO
      default:
        throw UnsupportedError('Realtime not supported for: $providerId');
    }
  }
}
```

## 🎯 **Objetivo de Integración**

### **✅ Estado Deseado**
```dart
// Uso unificado desde RealtimeService
final realtimeClient = await RealtimeService.getBestRealtimeClient();
await realtimeClient.connect();

// O específico por provider:
final openaiRealtime = await RealtimeService.getRealtimeClient('openai');
```

### **🏗️ Arquitectura Target**
```dart
// 1. Extender IAIProvider con capabilities realtime
abstract class IAIProvider {
  // Métodos existentes...
  
  // ✨ NUEVO: Realtime capabilities
  bool get supportsRealtime;
  Future<RealtimeVoiceClient?> createRealtimeClient();
}

// 2. OpenAIProvider implementa realtime
class OpenAIProvider implements IAIProvider {
  @override
  bool get supportsRealtime => true;
  
  @override
  Future<RealtimeVoiceClient?> createRealtimeClient() async {
    return OpenAIRealtimeVoiceClient();
  }
}

// 3. RealtimeService usa el registry dinámico
class RealtimeService {
  static Future<RealtimeVoiceClient?> getBestRealtimeClient() async {
    final registry = AIProviderRegistry.instance;
    
    // Busca providers con realtime en orden de prioridad
    for (final provider in registry.getProvidersByPriority()) {
      if (provider.supportsRealtime) {
        return await provider.createRealtimeClient();
      }
    }
    
    throw Exception('No realtime providers available');
  }
}
```

## 📋 **Plan de Integración - Fase 3**

### **Paso 1: Extender Interface IAIProvider (30 min)**
```dart
// lib/shared/ai_providers/core/interfaces/ai_provider.dart
abstract class IAIProvider {
  // Métodos existentes...
  String get providerId;
  Future<AIResponse> sendMessage({...});
  
  // ✨ NUEVOS: Realtime capabilities
  bool get supportsRealtime => false;
  Future<RealtimeVoiceClient?> createRealtimeClient() async => null;
  
  // ✨ NUEVO: Realtime models
  List<String> get availableRealtimeModels => [];
  String? get defaultRealtimeModel => null;
}
```

### **Paso 2: Implementar en OpenAIProvider (45 min)**
```dart
// lib/shared/ai_providers/implementations/openai_provider.dart
class OpenAIProvider implements IAIProvider {
  // Implementación existente...
  
  @override
  bool get supportsRealtime => true;
  
  @override
  List<String> get availableRealtimeModels => [
    'gpt-4o-realtime-preview-2024-10-01'
  ];
  
  @override
  String? get defaultRealtimeModel => 'gpt-4o-realtime-preview-2024-10-01';
  
  @override
  Future<RealtimeVoiceClient> createRealtimeClient() async {
    return OpenAIRealtimeVoiceClient();
  }
}
```

### **Paso 3: Crear RealtimeService Unificado (60 min)**
```dart
// lib/shared/ai_providers/core/services/realtime_service.dart
class RealtimeService {
  static Future<RealtimeVoiceClient> getBestRealtimeClient({
    String? preferredProvider,
    String? model,
  }) async {
    final registry = AIProviderRegistry.instance;
    
    // Si se especifica un provider, intentar usarlo
    if (preferredProvider != null) {
      final provider = registry.getProvider(preferredProvider);
      if (provider?.supportsRealtime == true) {
        return await provider!.createRealtimeClient();
      }
    }
    
    // Buscar el primer provider con realtime disponible
    final realtimeProviders = registry.getProvidersByPriority()
        .where((p) => p.supportsRealtime)
        .toList();
    
    if (realtimeProviders.isEmpty) {
      throw Exception('No realtime providers available. Configure providers with realtime support.');
    }
    
    return await realtimeProviders.first.createRealtimeClient();
  }
  
  static Future<List<String>> getAvailableRealtimeModels() async {
    final registry = AIProviderRegistry.instance;
    final models = <String>[];
    
    for (final provider in registry.getAllProviders()) {
      if (provider.supportsRealtime) {
        models.addAll(provider.availableRealtimeModels);
      }
    }
    
    return models;
  }
}
```

### **Paso 4: Migrar CallDependencyProvider (30 min)**
```dart
// lib/call/services/call_dependency_provider.dart
class CallDependencyProvider with ChangeNotifier {
  Future<RealtimeVoiceClient> getRealtimeClientForProvider(String providerId) async {
    // ✅ USA SISTEMA UNIFICADO en lugar de switch hardcodeado
    return await RealtimeService.getBestRealtimeClient(
      preferredProvider: providerId,
    );
  }
  
  // ✅ Método simplificado usando registry dinámico
  Future<RealtimeVoiceClient> getBestRealtimeClient() async {
    return await RealtimeService.getBestRealtimeClient();
  }
}
```

### **Paso 5: Actualizar YAML Config (15 min)**
```yaml
# assets/ai_providers_config.yaml
ai_providers:
  openai:
    enabled: true
    priority: 1
    display_name: "OpenAI GPT"
    capabilities: [text_generation, image_analysis, realtime_voice]  # ✨ NUEVO
    realtime:                                                       # ✨ NUEVO
      enabled: true
      models: ["gpt-4o-realtime-preview-2024-10-01"]
      default_model: "gpt-4o-realtime-preview-2024-10-01"
    models:
      text_generation: ["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"]
      
  google:
    enabled: true
    priority: 2
    display_name: "Google Gemini"
    capabilities: [text_generation, image_analysis]    # Sin realtime por ahora
    
  xai:
    enabled: true
    priority: 3
    display_name: "xAI Grok"
    capabilities: [text_generation]                    # Sin realtime por ahora
```

## 🎯 **Beneficios de la Integración**

### **1. Coherencia Arquitectónica**
- **Antes**: 2 sistemas separados (providers + realtime)
- **Después**: 1 sistema unificado con capabilities

### **2. Configuración YAML Única**
- **Antes**: Realtime hardcodeado en código
- **Después**: Realtime configurable desde YAML

### **3. Multi-Provider Realtime Ready**
- **Antes**: Solo OpenAI realtime
- **Después**: Cualquier provider puede implementar realtime

### **4. API Simplificada**
```dart
// ❌ ANTES: DI complejo
final di = CallDependencyProvider();
final client = di.getRealtimeClientForProvider('openai');

// ✅ DESPUÉS: API limpia
final client = await RealtimeService.getBestRealtimeClient();
```

## 🚀 **Extensibilidad Futura**

### **Google Realtime (Cuando esté disponible)**
```dart
class GoogleProvider implements IAIProvider {
  @override
  bool get supportsRealtime => true;  // ✨ Solo cambiar esto
  
  @override
  Future<RealtimeVoiceClient> createRealtimeClient() async {
    return GoogleRealtimeVoiceClient();  // ✨ Implementar cliente
  }
}
```

### **xAI Realtime (Cuando esté disponible)**
```dart
class XAIProvider implements IAIProvider {
  @override
  bool get supportsRealtime => true;
  
  @override
  Future<RealtimeVoiceClient> createRealtimeClient() async {
    return XAIRealtimeVoiceClient();
  }
}
```

## 📊 **Métricas de Éxito**

| Aspecto | Antes | Objetivo | Progreso |
|---------|-------|----------|----------|
| **Código Hardcoded** | Switch en DI | Zero switches | 🟡 Pendiente |
| **Configuración** | Solo código | YAML completo | 🟡 Pendiente |
| **Multi-provider** | Solo OpenAI | Cualquier provider | 🟡 Pendiente |
| **API Unificada** | 2 sistemas | 1 sistema | 🟡 Pendiente |
| **Extensibilidad** | Manual | Automática | 🟡 Pendiente |

## ⏱️ **Timeline Estimado**

| Tarea | Tiempo | Acumulado |
|-------|--------|-----------|
| Extender IAIProvider | 30 min | 30 min |
| OpenAIProvider realtime | 45 min | 1h 15min |
| RealtimeService unificado | 60 min | 2h 15min |
| Migrar CallDependencyProvider | 30 min | 2h 45min |
| Actualizar YAML config | 15 min | 3h |

**🎯 TOTAL ESTIMADO: 3 horas**

## 🎉 **Estado Post-Integración**

### **Resultado Final**
- ✅ **Sistema Unificado**: Providers + Realtime en una sola arquitectura
- ✅ **YAML-Driven**: Todo configurable externamente
- ✅ **Multi-Provider Ready**: Cualquier provider puede implementar realtime
- ✅ **API Simplificada**: Una sola manera de obtener realtime clients
- ✅ **Future-Proof**: Preparado para Google/xAI realtime

### **Puntuación Final Esperada**
**Desacoplamiento Total: 10/10** (Completamente Desacoplado)

---
*Este documento será actualizado conforme se complete la Fase 3 de integración realtime*
