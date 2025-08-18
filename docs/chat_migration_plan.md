# Plan de migración: Desacoplar el chat de proveedores y servicios

Fecha: 18-08-2025
Autor: (generado automáticamente)

## Resumen
Este documento analiza la estructura actual del código relacionada con el chat, mapea dónde está cada responsabilidad hoy y propone un plan detallado y ordenado para desacoplar el chat de los proveedores y servicios (OpenAI, audio, transcripción, TTS, etc.). Incluye una checklist accionable, criterios de calidad y pruebas mínimas.

---

## Requisitos extraídos
- Revisar la estructura actual y localizar funcionalidades relacionadas con el chat y los proveedores.
- Proponer dónde debe ir cada funcionalidad en una estructura desacoplada.
- Proponer un plan paso a paso para migrar y comprobar funcionamiento.

## Checklist principal (estado inicial)
- [ ] Análisis de código y mapeo de responsabilidades (hecho)
- [ ] Propuesta de estructura de carpetas y archivos (hecho)
- [ ] Plan de pasos de migración con criterios de verificación (hecho)
- [ ] Crear ramas/commits para cada paso (pendiente)
- [ ] Implementación incremental con tests y verificación (pendiente)

---

## Resumen del análisis (archivos clave y responsabilidades actuales)

Observaciones generales:
- Gran parte de la lógica del chat está dentro de `lib/providers/chat_provider.dart`. Este archivo contiene: gestión del estado, persistencia, envío de mensajes, reintentos, llamadas de voz, generación de TTS, coordinación con múltiples servicios, scheduling periódicos, y llamadas directas a servicios (p.ej., `AiChatResponseService`, `OpenAIService`).
- Hay muchos servicios en `lib/services/` que ya están parcialmente desacoplados (`openai_service.dart`, `image_request_service.dart`, `audio_chat_service.dart`, `voice_call_summary_service.dart`, `ai_chat_response_service.dart`, etc.) pero son consumidos directamente desde el `ChatProvider`.
- La UI (widgets y pantallas) consumen `ChatProvider` directamente mediante `provider` (`ChangeNotifierProvider`) — por ejemplo `lib/screens/chat_screen.dart`, `lib/widgets/voice_call_chat.dart`, `lib/widgets/audio_message_player.dart`.
- `lib/services/openai_service.dart` implementa la comunicación con OpenAI y TTS/STT. Existe además una abstracción `AIService` (`lib/services/ai_service.dart`) usada por `ChatProvider`.
- `main.dart` crea el `ChatProvider` en un `ChangeNotifierProvider` y pasa `onboardingData` antes de `loadAll()`.

Lista no exhaustiva de archivos relevantes encontrados y su responsabilidad actual:
- `lib/providers/chat_provider.dart`: estado del chat, lógica principal de envío/recepción, persistencia (SharedPreferences), manejo de audio, TTS, resúmenes, llamadas, detección de peticiones de imagen, scheduler periódico.
- `lib/services/openai_service.dart`: implementación concreta para OpenAI (transcripción, TTS, envío de mensajes al endpoint `/responses`).
- `lib/services/ai_service.dart`: interfaz/abstracción para servicios IA.
- `lib/services/ai_chat_response_service.dart`: orquestador/respuesta de chat (reintentos, parseo, extracción de imágenes, prompt handling) — usado por `ChatProvider`.
- `lib/services/audio_chat_service.dart`: manejador local de grabación / reproducción y hooks a TTS.
- `lib/services/image_request_service.dart`: heurística para detectar peticiones de imagen.
- `lib/services/memory_summary_service.dart`: resumido y persistencia de memoria / timeline.
- `lib/widgets/voice_call_chat.dart`: UI y mucha lógica de control de llamadas que interactúa con `ChatProvider` y `OpenAIService`.
- `lib/screens/chat_screen.dart`: UI principal del chat; llama a `chatProvider.sendMessage`, abre `VoiceCallChat` con `ChangeNotifierProvider.value`.
- `lib/main.dart`: inicialización y creación de `ChatProvider` en el árbol de widgets.


## Módulos compartidos entre chat y llamadas

Lista breve de módulos/archivos que se usan en ambos dominios y deben vivir en una carpeta/fachada compartida (`lib/core/`):

- IA / adaptadores de LLM
   - `lib/services/ai_service.dart` (fábrica/selector de servicios IA)
   - `lib/services/openai_service.dart` (implementación concreta)
   - `lib/services/gemini_service.dart` (implementación concreta)
   - Observación: widgets/controladores (p.ej. `lib/widgets/voice_call_chat.dart`, `lib/services/voice_call_controller.dart`) instancian `OpenAIService` directamente — conviene inyectar interfaces.

- Realtime / streaming
   - `lib/services/openai_realtime_client.dart`
   - `lib/services/voice_call_controller.dart` (usa cliente realtime)
   - Recomendación: mover clientes realtime a `lib/voice/clients/` y exponer interfaces públicas desde `lib/voice/`.

- Audio (TTS / STT)
   - `lib/services/google_speech_service.dart`
   - llamadas a TTS/STT dentro de `lib/services/openai_service.dart` (Whisper, endpoints de audio)
   - Android bindings en `android/.../MainActivity.kt` relacionados con TTS
   - Recomendación: definir `ITtsService` y `ISttService` en `lib/core/interfaces/` y que las implementaciones concretas vivan bajo `lib/services/<provider>/`.

- Cache / persistencia compartida
   - `lib/services/cache_service.dart` (usado por OpenAI, Google y widgets como `tts_configuration_dialog.dart`)
   - Recomendación: reubicar o reexportar desde `lib/core/cache/cache_service.dart` para señalizar su carácter compartido.

- Modelos / DTOs
   - `lib/models/*.dart` (Message, Image, AiChanProfile, ImportedChat, etc.) son consumidos por chat y por la capa de llamadas.
   - Recomendación: consolidar los modelos compartidos en `lib/core/models/` o `lib/shared/models/` y actualizar imports.

- Orquestador de respuestas / parsing
   - `lib/services/ai_chat_response_service.dart` contiene lógica de orquestación y detección de tags (`[audio]`, `[call]`, ...).
   - Recomendación: extraer las funciones de parsing/detección que necesiten llamadas a `lib/core/` para reutilizarlas desde `lib/voice/`.

Implicación práctica: crear `lib/core/interfaces/` y mover/copiar `cache_service.dart` y modelos a `lib/core/` es un primer paso de baja fricción que permite inyectar dependencias sin romper runtime.

## Propuesta de estructura desacoplada (target)

- `lib/chat/`
  - `models/` (Message, CallSummary, VoiceCallSummary, etc.)
  - `domain/` (casos de uso puros — interacciones del chat en lógica aislada)
  - `services/` (adaptadores para servicios IA, TTS, STT, image-gen)
  - `providers/` (adaptadores UI: ChangeNotifier, Riverpod wrappers que llaman a los casos de uso)
  - `repositories/` (persistencia: SharedPreferences, filesystem; interfaz + implementación)
  - `widgets/` (widgets específicos del chat que dependen solo de `providers`)
  - `screens/` (pantallas del chat)

- `lib/core/` (interfaces y utilidades comunes)
  - `interfaces/` (ej. `IChatRepository`, `IAIService`, `ITtsService`, `ISttService`)
  - `errors/`, `utils/`, `logging/`

- `lib/services/` (mantenemos servicios proveedores concretos — OpenAI, Google — como adaptadores que implementan las interfaces en `core/interfaces`)

- `lib/main.dart` dejar limpio: solo init, inyección de dependencias simples y routing.


### Separación explícita: Chat vs Llamadas

Importante: la lógica de llamadas de voz (UI de llamada, controladores de llamada, resumen de llamadas, grabación/streaming en tiempo real, heurísticas de start/end call, tonos de ring/colgado, etc.) NO debe vivir dentro de `lib/chat/` ni mezclarse con los casos de uso de chat. Esta lógica irá a un módulo/folder separado:

- `lib/voice/` o `lib/calls/` (escoger uno consistente para el repo):
   - `controllers/` (VoiceCallController, stream handlers)
   - `services/` (voice realtime adapters, speech streaming, summary generation específicos de llamadas)
   - `screens/` (UI de llamada: `voice_call_chat.dart` migrado aquí como pantalla específica de llamadas)
   - `models/` (VoiceCallSummary, call metadata)

Razonamiento: las llamadas tienen requisitos y dependencias runtime (streaming, mic access, timers y controladores) distintos a enviar/recibir mensajes de chat y deben poder evolucionar, desplegarse y testearse por separado.


## Mapeo recomendado: dónde irá cada funcionalidad actual

- Estado y UI
  - `lib/providers/chat_provider.dart` -> `lib/chat/providers/chat_provider.dart` (a mantener durante transición, pero reduciendo responsabilidades)
  - `lib/screens/chat_screen.dart` -> `lib/chat/screens/chat_screen.dart`
  - `lib/widgets/*` relacionados -> `lib/chat/widgets/`

- Modelos
  - `lib/models/*.dart` (Message, AiChanProfile, etc.) -> `lib/chat/models/`

- Servicios IA y periféricos
  - `lib/services/openai_service.dart` -> `lib/services/openai/openai_service.dart` (implementación concreta)
  - `lib/services/ai_service.dart` (interface) -> `lib/core/interfaces/ai_service.dart`
  - `lib/services/ai_chat_response_service.dart` -> `lib/chat/services/ai_chat_response_service.dart` (orquestador que implementa `IAIChatResponse`)
  - `lib/services/audio_chat_service.dart` -> `lib/chat/services/audio_service/` o `lib/services/audio_audiochat_service.dart`
  - `image_request_service.dart`, `prompt_builder.dart`, `voice_call_summary_service.dart`, `voice_call_controller.dart` -> `lib/chat/services/` o `lib/services/` según sean específicos del dominio o proveedor

- Persistencia y cache
  - Lógica de `saveAll`, `loadAll`, eventos y SharedPreferences -> `lib/chat/repositories/local_chat_repository.dart` que implemente `IChatRepository` en `lib/core/interfaces`.

- Scheduling / background jobs
  - `PeriodicIaMessageScheduler`, `PromiseService` -> `lib/chat/services/scheduler/` o `lib/chat/domain/schedulers.dart`

- Audio/Transcripción/TTS
  - Abstraer `GoogleSpeechService`, `OpenAIService.textToSpeech`, `OpenAIService.transcribeAudio` detrás de interfaces: `ISttService`, `ITtsService`, `IAudioProviderService`. Concretas en `lib/services/openai_*` o `lib/services/google_*`.

---

## Contrato pequeño (inputs/outputs, criterios)

- Inputs: llamadas a `ChatProvider.sendMessage(text, image?, model?)` desde UI.
- Outputs: actualización de `messages: List<Message>` observable, flags (`isTyping`, `isSendingImage`, etc.) y persistencia en `IChatRepository`.
- Errores: error en red o en proveedor -> `Message.status == failed` y callback `onError`.
- Success: `Message` assistant añadido y `Message.status == read` para user.

Criterios de éxito mínimos por paso: cada paso debe dejar la app funcional localmente (build + navegación + send message happy path) y los tests unitarios pertinentes deben pasar.

---

## Plan detallado por pasos (ordenado, incremental)

Nota: cada paso debe ser una rama git separada y contener tests mínimos.

1) Preparación (rápido)
   - [ ] Crear branch `chat/migration/prepare`.
   - [ ] Añadir directorio `lib/chat/` y `lib/core/interfaces/` vacíos.
   - [ ] Añadir tests skeleton `test/chat_migration/`.
   - Verificación: `flutter analyze` pasa sin errores de sintaxis adicionales.

2) Extraer modelos y tipos (baja fricción)
   - [ ] Mover/copalizar modelos usados por chat a `lib/chat/models/` (`Message`, `AiChanProfile`, `ImportedChat`, `EventEntry`, etc.).
   - [ ] Actualizar imports en `chat_provider.dart`, `chat_screen.dart`, `voice_call_chat.dart`.
   - Verificación: Build y run unitario de `widget_test.dart`.

3) Definir interfaces (contratos)
   - [ ] Crear interfaces en `lib/core/interfaces/`:
     - `IChatRepository` (save/load/clear/export/import)
     - `IAIService` (sendMessageImpl, getAvailableModels)
     - `IChatResponseService` (send wrapper used by provider)
     - `ITtsService` y `ISttService` si aplica
   - [ ] Implementar adaptadores **por delegación** que envuelvan las implementaciones actuales (p. ej. `OpenAIService` seguirá existiendo pero implementará `IAIService`).
   - Verificación: compila y tests de mock básicos.

4) Crear repositorio local (persistencia)
   - [ ] Implementar `lib/chat/repositories/local_chat_repository.dart` que use `SharedPreferences` y filesystem. Inicialmente adaptará la lógica que hoy está dentro de `ChatProvider.saveAll`/`loadAll`.
   - [ ] Cambiar `ChatProvider` para depender de `IChatRepository` en lugar de acceder directamente a `SharedPreferences`.
   - Verificación: importar/exportar chat y persistencia siguen funcionando.

5) Separar la lógica de envío y orquestación IA
   - [ ] Extraer la lógica de `sendMessage` (construcción de prompt, selección de modelo, detección de imagen, reintentos) a un caso de uso en `lib/chat/domain/send_message_usecase.dart` o `lib/chat/services/ai_chat_response_service.dart` que dependa únicamente de las interfaces (`IAIService`, `IChatRepository`).
   - [ ] Dejar en `ChatProvider` solo la coordinación (llamar al caso de uso, actualizar `messages` y flags).
   - Verificación: enviar mensaje en UI (happy path) funciona como antes.

6) Abstraer TTS/STT y audio
   - [ ] Definir `ITtsService` y `ISttService` y adaptar `OpenAIService` y `GoogleSpeechService` para implementar esas interfaces.
   - [ ] Refactorizar `AudioChatService` para depender de las interfaces y no llamar directamente a `OpenAIService`.
   - Verificación: grabar audio -> transcribir -> enviar mensaje sigue funcionando.

7) Extraer lógica de llamadas de voz (módulo independiente)
   - [ ] Crear módulo independiente `lib/voice/` o `lib/calls/` (escoger uno y usarlo de forma consistente).
   - [ ] Mover gran parte de la lógica de `voice_call_chat.dart`, `voice_call_controller.dart`, `voice_call_summary_service.dart`, `openai_realtime_client.dart`, `gemini_realtime_client.dart`, `hybrid_voice_call_service.dart` y controladores relacionados a `lib/voice/`.
   - [ ] Reducir `voice_call_chat.dart` en `lib/chat/widgets/` a UI que interactúe con la capa de llamadas mediante interfaces públicas del módulo `lib/voice/` (o mantener la UI en `lib/voice/screens/` si prefieres separar por completo la UI de llamadas).
   - Verificación: iniciar y terminar llamada, generar resumen y guardarlo en mensajes del chat a través de un adaptador público (p. ej. `VoiceModule.addCallSummaryToChat(...)`).

8) Limpiar `ChatProvider`
   - [ ] Eliminar dependencias directas sobre `OpenAIService`, `SharedPreferences`, y servicios concretos; inyectar interfaces via constructor o fábrica en `main.dart`.
   - [ ] Mantener `ChangeNotifier` y expone solo lo necesario para UI.
   - Verificación: `flutter analyze`, tests unitarios del provider (mocks).

9) Inyección de dependencias en `main.dart`
   - [ ] Crear un simple contenedor o factory (p. ej. `lib/core/di.dart`) que construya implementaciones concretas e inyecte a `ChatProvider`.
   - Verificación: arranque completo de la app con `ChatProvider` inyectado.

10) Tests y quality gates
   - [ ] Tests unitarios: casos básicos de `sendMessage` (mock `IAIService`), persistencia (mock `IChatRepository`), generación de TTS (mock `ITtsService`) y resumen de llamadas (mock `IChatRepository` + `IVoiceSummary`).
   - [ ] Lint y `flutter analyze` deben pasar.
   - [ ] Smoke test manual: abrir `ChatScreen`, enviar texto, enviar imagen, grabar nota de voz, iniciar llamada, exportar chat.

11) Documentación y limpieza final
   - [ ] Migrar widgets a `lib/chat/widgets/` (opcional en etapas)
   - [ ] Eliminar código duplicado y archivos obsoletos
   - [ ] Merge a `main` cuando todo esté probado

---

## Edge cases y riesgos
- Reintentos y estados `MessageStatus` deben preservarse exactamente (evitar duplicar mensajes en la migración).
- Criterios de llamadas (placeholder `[call][/call]`, `[start_call]`, `[end_call]`) son sensibles; mover la lógica sin tests puede introducir regresiones.
- Dependencias globales en `main.dart` y uso de `Provider.of(context)` tras awaits requieren cuidado (uso de `read`/capturar `navigator` antes de awaits).
- Concurrencia: varias llamadas a `notifyListeners()` y persistencia en `notifyListeners()` (actualmente `ChatProvider.notifyListeners` guarda en prefs) deben revisarse para no bloquear UI.

---

## Quality gates (mínimos)
- Build: `flutter analyze` -> PASS
- Unit tests: añadir al menos 3 tests (sendMessage happy path, persistencia, voice summary) -> PASS
- Manual smoke: enviar texto, enviar imagen, grabar nota voz, abrir y colgar llamada -> OK

---

## Próximos pasos (acción inmediata que puedo ejecutar)

Propongo un paso inmediato y de alto valor: crear las interfaces base y preparar una prueba de concepto moviendo/copializar los modelos compartidos. Esto permite inyección de dependencias y reduce el acoplamiento sin grandes cambios de runtime.

Acción propuesta (si confirmas la ejecuto ahora):

- [ ] Crear branch `chat/migration/prepare` y trabajar sobre él.
- [ ] Crear `lib/core/interfaces/` con interfaces mínimas:
   - `i_chat_repository.dart` (saveAll/loadAll/clear/import/export)
   - `i_ai_service.dart` (sendMessage, getAvailableModels, transcribe/synthesize signatures opcionales)
   - `i_tts_service.dart` y `i_stt_service.dart` (si decides incluir TTS/STT en la primera iteración)
- [ ] Copiar `lib/models/message.dart` y `lib/models/ai_chan_profile.dart` a `lib/chat/models/` como prueba de concepto (no eliminar los originales todavía).
- [ ] Actualizar `lib/providers/chat_provider.dart` para depender de `IChatRepository` e `IAIService` (inyección por constructor) pero mantener adaptadores que deleguen en las implementaciones actuales.
- [ ] Ejecutar `flutter analyze` y una verificación manual rápida (abrir ChatScreen y enviar un mensaje de texto) para asegurar que nada se rompe.

Verificación / criterios de éxito inmediatos:

- `flutter analyze` debe pasar sin errores.
- Flujo básico de chat (abrir pantalla, enviar texto) debe funcionar en el entorno local.

Si confirmas, procedo ahora a crear la rama y aplicar los cambios en commits atomizados. Puedo primero crear solo las interfaces y luego el movimiento de modelos si prefieres hacerlo en dos pasos.

### Deltas aplicados después de este documento

- Renombrado del modelo core `Image` a `AiImage` en `lib/core/models/image.dart` y actualización de todas las referencias a `models.AiImage` en el repo.
- Eliminación del `typedef Image = AiImage` para evitar ambigüedad con el widget `Image` de Flutter.
- Eliminación y migración de aliases antiguos (`ai_image`) en múltiples archivos: `chat_provider.dart`, `chat_screen.dart`, `message.dart`, `ai_chan_profile.dart`, `message_input.dart`, `ia_appearance_generator.dart`, `onboarding_utils.dart`, entre otros.
- Ajustes en barrels/imports y UI: removido `hide Image` en lugares donde ya no se exportaba `Image` desde el barrel; archivo `lib/core/models/index.dart` reexporta `core/models/image.dart` (ahora definiendo `AiImage`).
- Correcciones menores en imports y tipos en `lib/chat/models/*` (versiones de prueba) para mantener compatibilidad durante la migración.
- Resultado inmediato: `flutter analyze` reportó **No issues found** tras las correcciones de integración.

Estos deltas se realizaron para eliminar colisiones de nombres y permitir continuar la migración incremental sin introducir alias repetidos en la UI.

### Cambios recientes (delta)

- Se aplicaron parches en `lib/screens/chat_screen.dart` para mitigar lints de uso de `BuildContext` a través de gaps async:
   - Captura de `BuildContext ctx = context;` en closures antes de awaits donde se hacía navegación o se mostraban diálogos.
   - Conversión de las llamadas posteriores para comprobar `if (!ctx.mounted) return;` y uso de `Navigator.of(ctx)` / `ScaffoldMessenger.of(ctx)` en lugar de usar `context` directamente.
   - Refactor puntual de `_showModelSelectionDialog` para recibir explícitamente un `BuildContext ctx` y así evitar el uso del `State.context` tras awaits.

- Resultado del análisis estático tras los cambios (fecha: 18-08-2025):
   - `flutter analyze` sigue informando warnings/infos pero no errores fatales. Actualmente quedan ~21 issues (incluyendo avisos `use_build_context_synchronously` en `chat_screen.dart` y en `tts_configuration_dialog.dart`, usos de APIs deprecadas y algunos lints de estilo). Estos son de baja/mid prioridad y se pueden corregir con parches adicionales.

Recomendación inmediata: terminar la corrección consistente de los avisos `use_build_context_synchronously` (capturar `ctx` y usar `ctx.mounted` donde proceda) en `chat_screen.dart` y `tts_configuration_dialog.dart`, luego limpiar imports innecesarios reportados por el analizador.

---

## Notas finales
- Puedo automatizar los primeros pasos (crear archivos de interfaces y mover modelos) y ejecutar `flutter analyze` y tests rápidos. Indica si quieres que proceda con la implementación del paso 1 y 2 ahora.

---

## Inventario detallado y mapeo por archivo (auditoría)

He listado los archivos relevantes en `lib/` y propongo el mapeo recomendado para cada uno. Si algo falta en la lista, indícalo y lo incluyo.

- `lib/providers/`
   - `chat_provider.dart` -> mover a `lib/chat/providers/chat_provider.dart` (mantener ChangeNotifier pero con menos responsabilidades)
   - `onboarding_provider.dart` -> quedarse en `lib/providers/` o mover a `lib/onboarding/` si se desea.

- `lib/models/` (mover a `lib/chat/models/`)
   - `message.dart`, `ai_chan_profile.dart`, `imported_chat.dart`, `chat_export.dart`, `event_entry.dart`, `image.dart`, `system_prompt.dart`, `timeline_entry.dart`, `ai_response.dart`, `realtime_provider.dart`, `unified_audio_config.dart`

- `lib/services/` (clasificar en `lib/services/` y `lib/voice/` según aplique)
   - IA / proveedor de texto
      - `openai_service.dart` -> `lib/services/openai/openai_service.dart` (implementa `IAIService`)
      - `gemini_service.dart` -> `lib/services/gemini/gemini_service.dart` (implementa `IAIService`)
      - `ai_service.dart` -> `lib/core/interfaces/ai_service.dart` (interface)
      - `openai_realtime_client.dart`, `gemini_realtime_client.dart`, `realtime_client.dart` -> mover a `lib/voice/clients/` (si son usados por llamadas)

   - Audio / TTS / STT
      - `openai_tts_engine.dart`, `android_native_tts_service.dart`, `local_simple_tts_engine.dart`, `tts_engine.dart` -> `lib/services/tts/` o `lib/audio/tts/` y exponer `ITtsService`
      - `google_speech_service.dart` -> `lib/services/google/google_speech_service.dart` (implementa `ISttService` y `ITtsService` behaviors)
      - `audio_chat_service.dart`, `audio_playback_strategy.dart`, `audio_playback_strategy_factory.dart` -> `lib/chat/services/audio/` o `lib/audio/`

   - Chat orchestration
      - `ai_chat_response_service.dart` -> `lib/chat/services/ai_chat_response_service.dart` (caso de uso)
      - `image_request_service.dart`, `prompt_builder.dart`, `memory_summary_service.dart` -> `lib/chat/services/` o `lib/core/utils/`

   - Calls / voice (mover a `lib/voice/`)
      - `voice_call_controller.dart`, `voice_call_summary_service.dart`, `hybrid_voice_call_service.dart`, `promise_service.dart`, `promise_scheduler_service.dart`, `periodic_ia_message_scheduler.dart` -> `lib/voice/` (controllers/services/schedulers relacionados con llamadas)

   - Otros utilitarios
      - `cache_service.dart`, `subtitle_controller.dart`, `event_service.dart`, `ia_appearance_generator.dart`, `ia_bio_generator.dart`, `tone_service.dart` -> `lib/core/utils/` o `lib/services/utils/`

- `lib/widgets/` (mover a `lib/chat/widgets/` los widgets solo de chat)
   - `chat_bubble.dart`, `message_input.dart`, `audio_message_player.dart`, `typing_animation.dart`, `tts_configuration_dialog.dart`, `expandable_image_dialog.dart`, `floating_audio_subtitle.dart`, `unified_provider_selector.dart`.
   - `voice_call_chat.dart`, `voice_call_painters.dart` -> migrar a `lib/voice/screens/` y `lib/voice/widgets/` respectivamente.

- `lib/screens/`
   - `chat_screen.dart` -> `lib/chat/screens/chat_screen.dart`
   - `onboarding_screen.dart`, `initializing_screen.dart` -> `lib/onboarding/` o mantener en `lib/screens/`
   - `gallery_screen.dart`, `calendar_screen.dart` -> `lib/chat/screens/` o `lib/screens/` según convenga

---

Checkpoint: he auditado carpetas `lib/services`, `lib/providers`, `lib/models`, `lib/widgets` y `lib/screens` y añadí el inventario detallado en este documento. Próximo: si confirmas, empiezo a crear las interfaces en `lib/core/interfaces/` y mover una copia de `message.dart` y `ai_chan_profile.dart` a `lib/chat/models/` como prueba de concepto (pasos 1 y 2).
