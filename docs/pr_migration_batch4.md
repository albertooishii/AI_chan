# PR: Batch 4 — Sweep final (Plan y primer lote)

Propósito
- Completar la migración eliminando lecturas directas de `.env` y cualquier instanciación residual de runtimes fuera de `lib/core/runtime_factory.dart`.
- Garantizar que la rama `migration` se mantenga verde: `flutter analyze` + `flutter test` tras cada lote.

Decisión propuesta (elige una):
- Opción A (rápida): mantener `dotenv.load()` en `main.dart` y hacer que `lib/core/config.dart` sea el punto único para leer variables (es decir, reemplazar `dotenv.env` por `Config.get(...)`).
- Opción B (recomendada): crear `Config.initialize()` que carga `dotenv` y aplica overrides; actualizar `main.dart` para llamar `await Config.initialize()` en lugar de `dotenv.load()`. Mejora control y testabilidad.

Estrategia por lotes (ejecutaré en PRs pequeños):

Lote 1 (hoy) — preparar wrapper e infra
- Crear/actualizar `lib/core/config.dart` con `Future<void> initialize()` que llame a `dotenv.load()` y soporte overrides desde variables de entorno o parámetros.
- Cambiar `lib/main.dart` para llamar `await Config.initialize()` (si eliges Opción B) o documentar el comportamiento si eliges A.
- Ejecutar `flutter analyze` y `test/migration/check_runtime_instantiation_test.dart`.

Lote 2 — reemplazos en UI/providers
- Buscar `dotenv.env[...]` en widgets y providers; reemplazar por `Config.get(...)` o inyección desde `Provider`.
- Ejecutar `flutter analyze` y pruebas unitarias relevantes.

Lote 3 — reemplazos en servicios y adaptadores
- Reemplazar accesos a `dotenv.env` en servicios (si quedan) y asegurar que adaptadores requieran runtime por inyección.
- Ejecutar `flutter analyze` y la suite de tests completa.

Lote 4 — limpieza y CI
- Eliminar código obsoleto y añadir job CI que ejecute `flutter analyze` + `flutter test` + pruebas de migración.

Primer lote — archivos concretos y patch propuesto
- `lib/core/config.dart` — añadir `initialize()` y documentar `setOverrides(Map)` para tests.
- `lib/main.dart` — reemplazar `await dotenv.load()` por `await Config.initialize()` (si eliges opción B). Si prefieres opción A, añado un comentario explicativo y dejo la llamada como está.
- `test/test_setup.dart` — cambiar para usar `Config.initialize()` en su flujo (o dejarlo si `test/test_setup.dart` ya usa `dotenv.testLoad()`; lo revisaré durante el parche).

Comandos de verificación (ejecutaré estos tras aplicar el primer lote):

```bash
flutter analyze
flutter test test/migration/check_runtime_instantiation_test.dart
flutter test --no-pub -r expanded   # opcional: suite completa si el primer lote es pequeño
```

Entrega del PR
- Un PR pequeño con cambios en `lib/core/config.dart`, `lib/main.dart` y `test/test_setup.dart` (si se requiere). Ejecutaré `analyze` y tests antes de pedir revisión.

Si confirmas, aplico el Lote 1 ahora (opción recomendada: Opción B — implementar `Config.initialize()` y actualizar `main.dart`).
