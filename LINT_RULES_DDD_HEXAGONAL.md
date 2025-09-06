# 🏗️ Reglas de Lint para DDD + Arquitectura Hexagonal + DRY

## 📊 Resumen de Nuevas Reglas Activadas

### **Total de violaciones detectadas: 752**
- 🎯 **687 catch clauses sin especificar tipo** (`avoid_catches_without_on_clauses`)
- ⚡ **65 operaciones I/O lentas** (`avoid_slow_async_io`)  
- 🏗️ **Variables inmutables** (`prefer_final_parameters`, `prefer_final_in_for_each`)

---

## 🎯 **DDD/Hexagonal Architecture Rules**

### **Inmutabilidad (Value Objects & Domain Entities)**
```yaml
prefer_final_fields: true          # 🏗️ Campos finales en clases
prefer_final_parameters: true      # 🏗️ Parámetros inmutables por defecto  
prefer_final_in_for_each: true     # 🏗️ Variables inmutables en loops
prefer_final_locals: true          # 🏗️ Variables locales inmutables
```

### **Principio de Responsabilidad Única (SRP)**
```yaml
avoid_catches_without_on_clauses: true  # 🎯 Catch específico por responsabilidad
avoid_catching_errors: true            # 🎯 No catch genérico de Error
avoid_void_async: true                 # 🎯 async void problemático
```

### **Prevenir Dependencias Incorrectas**
```yaml
one_member_abstracts: false            # ✅ Permitir interfaces de un método (DDD ports)
avoid_classes_with_only_static_members: false  # ⚠️ Permitir Utils temporalmente
```

---

## 🔄 **DRY (Don't Repeat Yourself) Rules**

### **Eliminar Duplicación de Código**
```yaml
avoid_redundant_argument_values: true  # 🔄 Argumentos redundantes
avoid_unnecessary_containers: true     # 🔄 Widgets redundantes
prefer_collection_literals: true       # 🔄 Literals vs constructores
prefer_if_null_operators: true         # 🔄 ?? vs if/else
prefer_null_aware_operators: true      # 🔄 ?. vs null checks
prefer_spread_collections: true        # 🔄 Spread vs addAll()
```

### **Constructores DRY**
```yaml
sort_constructors_first: true          # 📋 Organización consistente
prefer_initializing_formals: true      # 🔄 this.field vs field = field
prefer_const_constructors: true        # 🔄 Constructores const
prefer_const_constructors_in_immutables: true  # 🔄 @immutable + const
```

---

## 🔒 **Safety & Best Practices**

### **Null Safety & Error Handling**
```yaml
avoid_null_checks_in_equality_operators: true  # 🔒 == operators seguros
avoid_returning_null_for_void: true           # 🔒 void methods consistentes
cancel_subscriptions: true                    # 🔒 Memory leaks
close_sinks: true                             # 🔒 Cerrar Streams
use_build_context_synchronously: true         # 🔒 BuildContext seguro
```

### **Performance**
```yaml
avoid_slow_async_io: true              # ⚡ I/O performance (65 violaciones)
prefer_const_literals_to_create_immutables: true  # ⚡ Performance
```

---

## 📖 **Code Quality & Readability**

### **Consistencia**
```yaml
curly_braces_in_flow_control_structures: true  # 📖 Braces siempre
prefer_contains: true                          # 📖 .contains() vs indexOf
prefer_function_declarations_over_variables: true  # 📖 Function declarations
prefer_if_elements_to_conditional_expressions: true  # 📖 Collection if
prefer_inlined_adds: true                          # 📖 Inline adds
```

### **Code Smells**
```yaml
avoid_empty_else: true                # 🧹 else vacíos
avoid_print: true                     # 🧹 print() prohibido - usar Log.*
```

---

## 🎨 **Flutter Específico**

```yaml
use_key_in_widget_constructors: true   # 🎨 Keys para performance
sized_box_for_whitespace: true         # 🎨 SizedBox vs Container
avoid_web_libraries_in_flutter: true   # 🎨 No dart:html
```

---

## 🚀 **Estrategia de Migración**

### **Fase 1: Info Level (Actual)**
```yaml
# En analyzer.errors - no rompe build
avoid_catches_without_on_clauses: info  # 687 violaciones
avoid_slow_async_io: info               # 65 violaciones  
prefer_final_parameters: info           # Por determinar
```

### **Fase 2: Warning Level (Futuro)**
```yaml
# Después de arreglar gradualmente
avoid_catches_without_on_clauses: warning
avoid_slow_async_io: warning
prefer_final_parameters: warning
```

---

## 📋 **Tests de Arquitectura Complementarios**

Las reglas de lint se complementan con tests automáticos:

- **`hexagonal_architecture_test.dart`** - Validar dependencias entre capas
- **`ddd_layer_test.dart`** - Principios DDD y SRP  
- **`duplication_prevention_test.dart`** - Detectar código duplicado
- **`over_abstraction_prevention_test.dart`** - Evitar sobre-ingeniería
- **`unused_code_detection_test.dart`** - Código no usado (ahora automático)

---

## 🎯 **Próximos Pasos**

1. **Revisar gradualmente** las 752 violaciones detectadas
2. **Aplicar fixes automáticos** con `dart fix --apply`  
3. **Priorizar violaciones críticas** (catch clauses, I/O lento)
4. **Subir nivel** de info → warning cuando estén corregidas
5. **Activar reglas experimentales** una vez establecidas las básicas

---

## 🔗 **Comandos Útiles**

```bash
# Ver violaciones por tipo
dart analyze | grep "avoid_catches_without_on_clauses" | wc -l

# Aplicar fixes automáticos  
dart fix --apply

# Ver qué se puede arreglar automáticamente
dart fix --dry-run

# Análisis completo
dart analyze

# Solo errores críticos
dart analyze --fatal-warnings
```
