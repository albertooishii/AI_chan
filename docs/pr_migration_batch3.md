PR title: migration: centralize AI runtime creation (Batch 3 — runtime factory + tests)

PR summary
---------
Motivación
- Centralizar la creación de runtimes AI (OpenAI/Gemini) en un único lugar para seguir el patrón Hexagonal/DDD.
- Evitar instanciaciones directas de `OpenAIService()` y `GeminiService()` dispersas por el código.
- Facilitar tests mediante inyección y `AIService.testOverride`.

Cambios principales
- `lib/core/config.dart` — getters centralizados para configuración y overrides para tests.
- `lib/core/runtime_factory.dart` — fábrica y caché central que crea y devuelve runtimes (único sitio que instancia OpenAI/Gemini).
- `lib/services/ai_service.dart` — delega la selección/obtención de runtimes a la fábrica.
- `lib/services/adapters/default_tts_service.dart` — usa `Config` y obtiene runtime via fábrica (casts seguros).
- `lib/core/di.dart` — composition root actualizado para inyección/caché de runtimes y adaptadores.
- `test/migration/import_sanity_test.dart` — prueba de regresión que falla si hay instanciaciones directas de `OpenAIService()` o `GeminiService()` fuera de `lib/core/runtime_factory.dart`.
- `docs/full_migration_plan.md` — Batch 3 reubicado y plan actualizado.

Verificación realizada localmente
- `flutter analyze` → No issues found!
- `flutter test` → suite completa pasada (incl. prueba de regresión)

Files changed (relevantes)
- lib/core/config.dart (nuevo / actualizado)
- lib/core/runtime_factory.dart (nuevo / actualizado)
- lib/services/ai_service.dart (modificado)
- lib/services/adapters/default_tts_service.dart (modificado)
- lib/core/di.dart (modificado)
- test/migration/import_sanity_test.dart (nuevo)
- docs/full_migration_plan.md (modificado)

Checklist (PR acceptance criteria)
- [x] Centralización: la creación de runtimes solo ocurre en `lib/core/runtime_factory.dart`.
- [x] Config: no hay lecturas directas de `.env` en import-time; `lib/core/config.dart` expone getters.
- [x] Tests: `test/migration/import_sanity_test.dart` añadido y pasa.
- [x] Compilación: `flutter analyze` limpio.
- [x] Tests: `flutter test` pasa localmente.

Notas adicionales y recomendaciones
- Policy: `AIService.select` ahora es un fallback documentado — preferir resolución por DI/fábricas desde `lib/core/di.dart`.
- Next: hacer sweep por lotes (3–6 ficheros) para reemplazar instanciaciones residuales y renombrar adaptadores de perfil.

Suggested git commands (copy/paste locally)
```bash
# verificar cambios
git status --porcelain

# añadir cambios relevantes y commitear
git add docs/full_migration_plan.md lib/core/config.dart lib/core/runtime_factory.dart lib/services/ai_service.dart lib/services/adapters/default_tts_service.dart lib/core/di.dart test/migration/import_sanity_test.dart docs/pr_migration_batch3.md

git commit -m "migration(batch3): centralize AI runtime creation, use Config and add migration sanity test"

# push la rama actual
git push origin HEAD

# crear PR con GitHub CLI (opcional)
# gh pr create --base migration --title "migration: centralize AI runtime creation (Batch 3)" --body "Centraliza creación de runtimes (OpenAI/Gemini) en runtime_factory; refactoriza AIService.select y añade prueba de regresión."
```

---
Si quieres, puedo:
- A) Ejecutar los comandos git (commit + push) y crear el PR desde esta sesión (necesitaría permiso para ejecutar comandos). o
- B) Solo preparar el PR body y marcarlo como listo (ya hecho: `docs/pr_migration_batch3.md`), y esperar tu revisión.

Dime qué prefieres y procedo.
