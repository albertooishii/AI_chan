# Plan de Migración Completa del Dominio Chat y Módulos Relacionados

Fecha: 19 de agosto de 2025
Branch actual / objetivo: `migration` (cambios commiteados en esta rama)

Resumen de cambios recientes (estado a 2025-08-19 -> actualizado ahora):
- Migración: se movieron las implementaciones canónicas a `lib/core/services/` y se eliminaron las implementaciones legacy en `lib/services/`.
- Compatibilidad: se añadieron shims / re-exports donde fue necesario y se limpiaron imports rotos.
- Tests: se añadieron tests de persistencia/import/export (`test/onboarding/persistence_test.dart`) y varios tests de onboarding/chat; la suite local completa pasó.
- Fixes: se corrigieron fallos de persistencia detectados por los tests (ajustes en `lib/utils/storage_utils.dart` y `lib/chat/repositories/local_chat_repository.dart`).
- Analyze: `flutter analyze` actualmente no reporta issues ("No issues found!").
- Commit & push: cambios commiteados y pusheados a `origin/migration` (commit incluye tests y fixes de persistencia/import/export).

Estado objetivo: dejar `lib/core/services/` como fuente canónica, eliminar duplicados y mantener la API estable para providers y adaptadores; preparar la rama `migration` para push/PR.

Este documento consolida la migración que ya iniciamos (chat) y la extiende a los demás contextos/productos del app: onboarding, llamadas (voice), import/export JSON y calendario. Está escrito como un plan ejecutable por etapas, siguiendo principios DDD (secciones por bounded context), y usando la estrategia de "Adaptadores + Interfaces" (Opción A) que ya comenzamos.

Objetivos generales
- Desacoplar la lógica de negocio del proveedor (OpenAI, Gemini/Google, etc.).
- Tener modelos canónicos en `lib/core/models/` y un set de interfaces en `lib/core/interfaces/`.
- Implementar adaptadores por proveedor en `lib/services/adapters/` y fábricas en `lib/core/di.dart`.
- Permitir migraciones incrementales y pruebas locales (smoke runs) sin cortar la app.
- Asegurar cobertura de tests mínima por contexto (happy path + 1-2 edge cases).

Cómo leer este documento
- Cada sección es un bounded context (Onboarding, Chat, Calls, Import/Export, Calendar).
- Para cada contexto hay: contrato mínimo, pasos de migración, artefactos a crear/mover, tests mínimos, riesgos y criterios de éxito.

---

## 1) Resumen de Contextos (DDD / Bounded Contexts)
- Onboarding: generación de biografía, imagen/aseappearance, configuración inicial del perfil de AiChan.
- Chat: mensajería, historial, AI responses, mensajes multimedia (imágenes/audio).
- Calls (Llamadas/Voice): llamadas en tiempo real o emuladas (Orquestador Gemini), STT/TTS, control de sesión de llamada.
- Import/Export: importar chats desde JSON, exportar conversaciones y perfiles.
- Calendar/Agenda: entradas de calendario, recordatorios, timeline y sincronización.

---

## 2) Contrato y criterios transversales
- Inputs: DTOs canónicos en `lib/core/models/` (Message, AiResponse, AiImage, Profile, TimelineEntry, RealtimeProvider, UnifiedAudioConfig, ...).
- Interfaces: `ISttService`, `ITtsService`, `IAIService`, `IChatRepository`, `IProfileRepository`, `IImportExportService`, `ICalendarService`.
- Error modes: transcripción fallida, TTS no disponible, LLM rate-limit, fallos de red.
- Éxito mínimo: cada contexto puede ejecutarse localmente con un provider «mock» y con un provider real (cuando esté disponible) sin cambios en la lógica de negocio.

---

## 3) Onboarding (biografía y apariencia)
Contrato / Outputs
- Input: prompts y/o formularios del usuario.
- Output: `AiChanProfile` con `biography`, `appearance` (imagen/seed), `voiceConfig` opcional.


**Progreso actual:**
- [x] Modelos canónicos (`AiChanProfile`, `AiImage`, `Appearance`) en `lib/core/models/`.
- [x] Interfaz `IProfileService` creada en `lib/core/interfaces/`.
- [x] Adaptador `openai_profile_adapter.dart` implementado y testeado.
- [ ] Adaptador `google_profile_adapter.dart` pendiente (puede ser stub/fake).
- [x] Fábrica DI `getProfileServiceForProvider` añadida en `lib/core/di.dart`.
- [x] Wiring en el provider de onboarding para usar la interfaz (ya usa `IProfileService` vía DI en `OnboardingProvider`).
- [x] Tests unitarios y de persistencia añadidos (incluye casos de import/export y recarga); suite local pasó.

**Siguiente paso:**
- Refactorizar el provider de onboarding para usar `IProfileService` vía la fábrica DI.
- Implementar (o stubear) el adaptador Google si se requiere compatibilidad multi-proveedor.

**Notas:**
- La CI está activa y los tests de onboarding pasan correctamente.
- El adaptador OpenAI está desacoplado y testeable con mocks/fakes.

Riesgos & Notas
- Generación de imagen puede depender de políticas de uso de terceros.
- Volcar la imagen en storage (local vs cloud) debe abstraerse por `IStorageService`.

Criterio de éxito
- Onboarding funciona con provider `mock` y con provider `openai/google` (si keys disponibles) sin editar la UI.

Checklist
- [x] Mover `AiChanProfile`, `AiImage`, `Appearance` a `lib/core/models/` y actualizar barrels
- [x] Crear `IProfileService` en `lib/core/interfaces/` con métodos documentados
- [x] Implementar adaptadores `openai_profile_adapter.dart` (Google adapter pendiente)
- [x] Añadir `getProfileServiceForProvider` en `lib/core/di.dart`
- [x] Refactor UI/logic de onboarding para usar `IProfileService` (OnboardingProvider usa DI)
- [x] Añadir tests unitarios e integración (mock LLM, mock storage) y tests de persistencia/import/export

---

## 4) Chat (estado actual: en progreso)
Contrato / Outputs
- Messages: `Message` (texto, author, timestamp, optional AiImage, audio refs).
- Realtime: `IRealtimeClient` con métodos `connect`, `appendAudio`, `requestResponse`, `updateVoice`, `close`.

Pasos de migración (prioridad alta)
1. Finalizar canonicalización de modelos en `lib/core/models/` (ya comenzado).
2. Verificar/crear interfaces en `lib/core/interfaces/` para IA, STT, TTS, ChatRepository.
3. Completar adaptadores existentes (`openai_realtime_client.dart`, `gemini_realtime_client.dart` — orquestador emulado) y registrarlos en `lib/core/di.dart` con `getRealtimeClientForProvider`.
4. Refactorizar consumidores (providers, widgets, services) para inyectar `IRealtimeClient` y `IChatRepository` en vez de instancias concretas.
5. Tests:
   - Unit: `ChatProvider` con un `IRealtimeClient` falso que emule pasos.
   - Integration: smoke test enviar mensaje y recibir respuesta (mock LLM) + audio path generado.
6. Sanear imports: reemplazar `AiImage` por `AiImage` y usar `package:ai_chan/core/models.dart` (barrel) — tarea en curso.

Riesgos
- Reemplazo masivo de tipos puede romper archivos si se hace sin pruebas. Hacer migración por lotes.

Criterio de éxito
- `flutter analyze` sin errores y prueba manual de chat (envío de mensaje → respuesta) funcionando con provider mock y con OpenAI realtime si se desean.

Checklist
 - [x] Completar canonicalización de modelos en `lib/core/models/` (Message, AiImage, Profile, TimelineEntry)
- [ ] Añadir/validar interfaces: `IRealtimeClient`, `IChatRepository`, `IChatResponseService` en `lib/core/interfaces/`
 - [x] Registrar `getRealtimeClientForProvider` en `lib/core/di.dart`
- [ ] Refactor `ChatProvider`, widgets y servicios para usar interfaces en vez de implementaciones concretas
- [ ] Sustituir `AiImage` por `AiImage` en todo el repo (por lotes)
- [ ] Tests: unitarios para `ChatProvider` con mock `IRealtimeClient`; integration smoke test

Detalle extraído de `docs/chat_migration_plan.md`

- Resumen rápido del estado actual en la rama `chat/migration/prepare`:
   - Se implementaron y actualizaron interfaces parciales (`IAIService`, `ISttService`) y adaptadores (`OpenAIAdapter`, `GeminiAdapter`, `OpenAISttAdapter`).
   - `AudioChatService.synthesizeTts` y transcripción parcial ya usan fábricas DI (`getIAIServiceForModel`, `getSttService`).
   - Se añadió `GeminiCallOrchestrator` (emulación realtime via STT -> Gemini -> TTS) y `getRealtimeClientForProvider` en DI.
   - `VoiceCallController` fue adaptado para resolver el cliente realtime vía la fábrica de DI.

- Tareas con estado (extracto):
   - [DONE] Crear branch `chat/migration/prepare` y preparar estructura inicial.
   - [DONE] Crear adaptadores iniciales y algunas interfaces (`IAIService`, `ISttService`, OpenAI/Gemini adapters).
   - [DONE] Reemplazar instancias directas de `OpenAIService()` en puntos clave por llamadas via DI.
   - [PARTIAL] Consolidar modelos en `lib/core/models/` (trabajo iniciado, queda sanear imports y barrels).
   - [PARTIAL] Completar `IChatRepository` y wiring de `ITtsService` (algunos adaptadores ya creados).
   - [PENDING] Extraer módulo `lib/voice/` de forma completa y añadir tests unitarios para Chat y Calls.

- Notas importantes extraídas:
   - Mensajes de audio (notas de voz dentro de conversaciones) pertenecen al dominio `chat` y se mantienen allí; las llamadas en tiempo real son un módulo separado (`calls/voice`).
   - Comportamiento provider-specific: si el audio provider es `google` → llamadas usan Gemini + Google STT/TTS; si es `openai` → se usa OpenAI Realtime.


---

## 5) Calls / Voice (orquestador Gemini y OpenAI Realtime)
Contrato
- `IRealtimeClient` es el contrato común. Por provider:
  - `openai` → `OpenAIRealtimeClient` (usa streaming websocket/configs existentes).
  - `google` → `GeminiCallOrchestrator` (emulación: STT -> LLM -> TTS).

Pasos de migración
1. Crear/validar `ISttService` y `ITtsService` (ya existentes, comprobar adaptadores google/openai).
2. Finalizar `GeminiCallOrchestrator` y añadir tests de integración local:
   - Simular envío de audio file -> orquestador -> devuelve audio bytes.
3. Registrar fábrica `getRealtimeClientForProvider` en `lib/core/di.dart` (hecho parcialmente).
4. Refactor `VoiceCallController` para aceptar `IRealtimeClient` (ya en progreso).
5. Tests:
   - Unit: orquestador con STT/TTS mocks.
   - Smoke: iniciar llamada local con mock LLM y verificar flujo.

Riesgos
- Latencia por escritura/lectura de archivos temporales (emulación). Considerar buffers y chunking.

Criterio de éxito
- Llamada end-to-end emulada funciona localmente (transcribe -> LLM -> synthesize).

Checklist
 - [x] Validar `ISttService` y `ITtsService` en `lib/core/interfaces/`
- [ ] Finalizar `GeminiCallOrchestrator` y `OpenAIRealtimeClient` en `lib/features/calls/` o `lib/services/`
 - [x] Registrar fábrica `getRealtimeClientForProvider` en `lib/core/di.dart` (si no está)
 - [x] Refactor `VoiceCallController` para aceptar `IRealtimeClient` inyectado
- [ ] Tests: unitarios para orquestador con STT/TTS mocks y smoke test emulado

---

## 6) Import / Export JSON
Contrato
- `IImportExportService` con `importChatFromJson(File)` y `exportChatToJson(Chat)`.

Pasos
1. Canonicalizar modelos usados en import/export (Chat, Message, Profile).
2. Implementar `IImportExportService` con adaptadores: `json_import_export.dart`.
3. Wire UI: sección de settings o screen de import/export que use la interfaz.
4. Tests: importar archivo de muestra y comparar estructura serializada.

Notas
- Definir la versión del esquema (v1, v2) para permitir migraciones futuras.

Checklist
- [ ] Definir esquema JSON y versionado (v1)
- [ ] Implementar `IImportExportService` en `lib/core/interfaces/`
- [ ] Crear adaptador `json_import_export.dart` en `lib/services/adapters/`
- [x] Utilidades de import/export implementadas: `ChatJsonUtils.importAllFromJson`, `ChatExport`, `ImportedChat`, `StorageUtils.saveImportedChatToPrefs` y `LocalChatRepository.exportAllToJson`/`importAllFromJson`.
- [x] Tests: importar/exportar roundtrip y casos corruptos añadidos (`test/onboarding/persistence_test.dart`).
- [ ] Integrar UI (settings/screen) para importar/exportar y usar la interfaz (pendiente si se quiere UI dedicada)

---

## 7) Calendar / Agenda
Contrato
- `ICalendarService` con métodos `createEvent`, `listEvents`, `importEvents`.

Pasos
1. Diseñar modelo `CalendarEntry` y colocarlo en `lib/core/models/calendar_entry.dart`.
2. Crear interfaz `ICalendarService` y un `LocalCalendarAdapter`.
3. Integrar con timeline/tareas (TimelineEntry canonicalizado ya).
4. Tests: crear y listar evento.

Notas
- Integraciones con calendarios externos (Google Calendar) se tratan como adaptadores adicionales.

Checklist
- [ ] Diseñar `CalendarEntry` en `lib/core/models/calendar_entry.dart`
- [ ] Crear `ICalendarService` en `lib/core/interfaces/`
- [ ] Implementar `LocalCalendarAdapter` básico
- [ ] Integrar con `EventTimelineService` y `MemorySummaryService`
- [ ] Tests: crear y listar evento básico

---

## 8) Plan de trabajo por oleadas (sprints pequeños)
Oleada 1 (1-3 días)
- Completar canonicalización de modelos faltantes (AiImage, Message, Profile, TimelineEntry) — mayormente completado (revisar barrels y imports por lotes).
- Finalizar `lib/core/models/index.dart` barrel (hay `lib/core/models/index.dart` presente; validar exports adicionales).
- Ejecutar `flutter analyze` y arreglar imports rotos (se ejecutó y está limpio localmente).

Oleada 2 (3-7 días)
- Onboarding: interfaces + adaptadores + tests básicos.
- Chat: terminar reemplazos de imports y tipos, asegurar `ChatProvider` compila.

Oleada 3 (4-10 días)
- Calls: terminar `GeminiCallOrchestrator` y wiring en DI; refactor `VoiceCallController`.
- Crear tests de integración para llamadas.

Oleada 4 (2-4 días)
- Import/Export y Calendar: modelos, interfaces, adaptadores básicos y tests.

---

## Gallery / Image Viewer (UI / utilería)

Checklist
- [ ] Centralizar componentes de galería en `lib/features/media/` o `lib/widgets/media/`
- [ ] Definir `IMediaStorage` si es necesario para subir/guardar imágenes
- [ ] Actualizar `Message` y `ChatBubble` para usar `AiImage` y rutas locales (imageDir)
- [ ] Tests: abrir galería y ver imágenes desde mensajes

---

## Checklist global (entrega / PR)
- [x] `flutter analyze` limpio (local)
- [x] Tests unitarios básicos añadidos por contexto y tests de persistencia/import/export añadidos
- [ ] PRs atómicas por oleada con cambios documentados en `docs/` (pendiente cuando se abra PRs)
- [ ] Job CI ejecutando `flutter analyze` y tests (pendiente)

---

## 9) Calidad, CI y checks
- En cada PR: `flutter analyze` y tests unitarios que toquen los ficheros cambiados.
- Añadir un job de CI que ejecute `flutter analyze` y tests.
- Para cambios de modelo: incluir un migrator y pruebas de compatibilidad JSON (si aplica).

## Tests recomendados (unitarios, integración y regresión)

Resumen: añadir una combinaci n de tests unitarios, tests de integración "smoke" y tests de regresi n autom e1ticos para asegurar que la migraci f3n no vuelva a introducir imports legacy ni dependencias directas a proveedores.

Estrategia general
- Unit tests: prueban l f3gica aislada (providers, servicios, orquestador) usando mocks/fakes (recomendado: `mocktail`).
- Integration / smoke tests: prueban flujos esenciales con fakes que imitan providers externos (LLM, STT, TTS) sin requerir keys.
- Regression tests: scripts que escanean el c f3digo para detectar patrones indeseados (p.ej. `package:ai_chan/core/models.dart` o `import .* as models`). Ya tenemos `test/migration/import_sanity_test.dart` y conviene ampliarla.

Ficheros de test sugeridos y objetivos
- test/migration/import_sanity_test.dart — ya existente: detectar imports legacy y alias `as models`.
- test/migration/di_resolution_test.dart — verifica que las f e1bricas en `lib/core/di.dart` resuelven objetos y que podemos inyectar fakes.

- Chat
   - test/chat/chat_provider_test.dart (unit): mock `IRealtimeClient` que emite eventos de texto/audio; assert: mensajes cambian de `sending` a `sent/read` y el `ChatProvider` guarda respuestas.
   - test/chat/chat_smoke_test.dart (integration): usa un `FakeRealtimeClient` que devuelve una respuesta y una ruta de audio; assert: la interfaz de usuario (provider) recibe el audioPath y el mensaje de respuesta.

- Calls / Orquestador
   - test/calls/gemini_orchestrator_test.dart (unit): mock `ISttService` y `ITtsService`; assert: orquestador llama en orden STT -> LLM -> TTS y devuelve bytes de audio.
   - test/calls/voice_call_controller_smoke_test.dart (integration): instanciar `VoiceCallController` con un `FakeRealtimeClient`, simular inicio y cierre de llamada; assert: estados esperados y resumen final.

- Onboarding
   - test/onboarding/profile_service_test.dart (unit): mock `IAIService` + `IStorage`; assert: `generateBiography` produce campos esperados y `saveProfile` persiste.

- Import/Export
   - test/import_export/roundtrip_test.dart (integration): importar un JSON de ejemplo en `test/assets/` y exportarlo; assert: roundtrip id e9ntico o normalizado por esquema.

- Calendar
   - test/calendar/calendar_service_test.dart (unit): `LocalCalendarAdapter` create/list events.

Mocking y fakes
- Recomiendo `mocktail` (sin necesidad de generar código) o `mockito` si prefieres generated mocks.
- Crear fakes minimalistas en `test/fakes/` (p.ej. `fake_realtime_client.dart`, `fake_stt.dart`, `fake_tts.dart`) que implementen las interfaces de `lib/core/interfaces/`.

Reglas de regresión (tests de seguridad)
- Mantener `test/migration/import_sanity_test.dart` actualizado y ampliar con:
   - comprobación de que `lib/core/models.dart` es el barrel usado (en lugar de `index.dart`).
   - detectar imports con alias `as models`.
   - detectar referencias directas a adaptadores concretos desde providers (p.ej. `OpenAIAdapter` usado sin pasar por `di.dart`).

Integración en CI
- Job de GitHub Actions (o similar) que ejecute en cada PR:
   - flutter analyze
   - flutter test (tests unitarios + migration tests)
   - opcional: un job nightly que ejecute los smoke/integration tests más lentos.

Ejemplos de aserciones concretas (para cada test sugerido)
- chat_provider_test.dart: tras simular la respuesta del realtime, `expect(provider.messages.last.sender, MessageSender.assistant);` y `expect(provider.messages.last.status, MessageStatus.sent);`.
- gemini_orchestrator_test.dart: verificar llamadas ordenadas con `verify(() => mockStt.transcribe(...)).called(1);` y `expect(audioBytes.length, greaterThan(0));`.

Prioridad inicial
- Añadir y estabilizar: `test/migration/import_sanity_test.dart`, `test/chat/chat_provider_test.dart`, `test/calls/gemini_orchestrator_test.dart`.
- Luego: smoke tests y roundtrip import/export.

Notas finales
- Mantener tests atómicos y rápidos. Para tests que dependan de I/O pesado (audio), marcar como integration y ejecutarlos en pipelines separados o nightly.


---

## 10) Rollback y mitigación
- Hacer cambios en ramas pequeñas y atómicas.
- Mantener feature flags si un cambio puede romper runtime.
- Revertir PR rápidamente si `flutter analyze` o tests fallan en CI.

---

## 11) Artefactos y mapeo a ficheros (sugerido)
- `lib/core/models/` (ya en progreso): Message, AiImage, AiResponse, Profile, TimelineEntry, CalendarEntry, RealtimeProvider, UnifiedAudioConfig
- `lib/core/interfaces/`: IAIService, ISttService, ITtsService, IChatRepository, IProfileService, IImportExportService, ICalendarService
- `lib/services/adapters/`: openai_realtime_client.dart, gemini_realtime_client.dart, google_stt_adapter.dart, google_tts_adapter.dart, openai_stt_adapter.dart, default_tts_service.dart, json_import_export.dart
- `lib/core/di.dart`: fábricas `getXForProvider(provider)`
- `test/`: tests por contexto (chat_test.dart, onboarding_test.dart, calls_orchestrator_test.dart, import_export_test.dart)

---

## 12) Checklist de aceptación por contexto (al entregar)
- Onboarding: ✅ Biografía y apariencia generadas vía `IProfileService` y tests verdes.
- Chat: ✅ Chat funciona con interfaces y `flutter analyze` limpio.
- Calls: ✅ Orquestador Gemini emulado produce audio de respuesta.
- Import/Export: ✅ Importa/exporta JSON de ejemplo.
- Calendar: ✅ Crear/listar evento básico.

---

## 13) Próximos pasos inmediatos (qué haré si me das luz verde)
1. Añadir y refinar este documento en `docs/full_migration_plan.md` (hecho si aceptas).
2. Terminar la migración restante de `AiImage` en los ficheros que quedan (por lotes) y ejecutar `flutter analyze` tras cada lote.
3. Finalizar wiring del orquestador Gemini y añadir tests unitarios básicos.

Si quieres, empiezo ahora mismo con el punto 2: busco referencias restantes a `AiImage` y aplico parches por lotes (3–5 archivos por batch), ejecutando `flutter analyze` tras cada lote y reportando progresos.

---

Si quieres que reordene las prioridades o añada más detalles (scripts de CI, ejemplos de tests, o plantillas de interfaces), dime cuál prefieres y lo incorporo.
