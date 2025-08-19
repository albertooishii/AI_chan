# AI-chan

AI-chan es una "novia virtual": una aplicación experimental que crea una compañera conversacional personalizada. La app combina chat con memoria contextual, llamadas/nota de voz con prosodia, y generación de avatar a partir de una ficha de apariencia creada por IA. Está pensada para experimentación, investigación y uso personal responsable — no para suplantación, abuso ni usos ilegales.

Principales características

- Chat con contexto y memoria: la IA mantiene parte de la historia y usa una ficha de perfil para dar continuidad a la relación.
- Llamadas y notas de voz: prosodia y formato adaptados para sonar más naturales (TTS/STT cuando esté disponible).
- Generación de avatar: creación automática de una ficha de apariencia (JSON) y generación de imagen a partir de ella.
- Onboarding guiado: formulario inicial para crear el perfil de la IA (nombre, país, historia, fecha de nacimiento, y más).

Este repositorio es experimental. Respeta consentimiento, edad legal y las políticas de los proveedores de IA que uses.

## Onboarding — qué recoge y por qué

El flujo de onboarding crea la ficha `onboarding_data` que luego alimenta los prompts y generadores. Campos principales (actuales):

- Tu país (para localización e idioma)
- Tu nombre
- Fecha de nacimiento
- País de la AI-Chan
- Nombre de la AI-Chan
- Historia breve de cómo se conocieron (puede generarse automáticamente)

El onboarding se guarda en `SharedPreferences` bajo la clave `onboarding_data` y se puede exportar/importar en formato JSON.

## Cómo funciona a alto nivel (sin exponer prompts completos)

- La app construye un objeto de sistema (JSON) que contiene el perfil, la hora, mensajes recientes y unas instrucciones del sistema. Ese objeto se envía al servicio de IA (OpenAI / Gemini) para generar texto, llamadas o prompts de imagen.
- Para generar avatar, la app pide a la IA una ficha de apariencia estricta (JSON) y, a partir de ella, genera un prompt para un servicio de imágenes. El proceso está en `lib/services/ia_appearance_generator.dart`.
- Las instrucciones y reglas (persona, límites de lenguaje, reglas para fotos, formato de caption de imagen, etc.) están en `lib/services/prompt_builder.dart` y se usan por `lib/services/openai_service.dart` al construir solicitudes.
- Los logs de desarrollo (prompts y respuestas) se guardan en `debug_json_logs/` para depuración; revisa y limpia esos ficheros antes de compartir el repositorio públicamente.

## Privacidad y seguridad

- Nunca subas tus claves a un repositorio público. Usa el archivo `.env` (está en `.gitignore`).
- Revisa `debug_json_logs/` y borra o anonimiza cualquier dato sensible antes de publicar.
- La app puede generar contenido íntimo y/o imágenes; respeta las leyes locales, la edad de las personas implicadas y las políticas de los proveedores de IA. Hay opciones de configuración para limitar contenido explícito desde el onboarding (si las activas).

## Variables de entorno (`.env`)

Usa el archivo ` .env.example ` incluido en la raíz como referencia y renómbralo a `.env` con tus claves privadas. Ejemplo (extracto de `.env.example`):

```env
# Tamaño de bloque para resúmenes de memoria (por defecto 32 si vacío)
SUMMARY_BLOCK_SIZE=32

# Claves Gemini (principal y fallback opcional)
GEMINI_API_KEY=pon_aqui_tu_clave_gemini
GEMINI_API_KEY_FALLBACK=

# Clave OpenAI (para voz / imágenes si corresponde)
OPENAI_API_KEY=pon_aqui_tu_clave_openai

# Voz por defecto (alloy|ash|ballad|coral|echo|sage|shimmer|verse)
OPENAI_VOICE=sage

DEFAULT_TEXT_MODEL=gemini-2.5-flash
DEFAULT_IMAGE_MODEL=gpt-4.1-mini
```

Notas:

- El archivo `.env` está en `.gitignore` por seguridad; no subas tus claves.
- Ajusta `DEFAULT_TEXT_MODEL` y `DEFAULT_IMAGE_MODEL` según el proveedor que uses (OpenAI, Gemini/Vertex, etc.).
- Si `GEMINI_API_KEY` falla por cuota/permiso (401/403/429), la app intentará `GEMINI_API_KEY_FALLBACK` automáticamente si está definida.

## Instalación y ejecución rápida

Requisitos: Flutter (canal `stable`) y los SDKs nativos de las plataformas que quieras probar.

1. Clona el repositorio:

```bash
git clone <tu-repo>.git
cd ai_chan
```

2. Instala dependencias (o usa el Makefile para preparar todo):

```bash
flutter pub get
```

3. Crea tu `.env` renombrando ` .env.example ` y colocando tus claves reales, o usa el asistente interactivo:

```bash
make setup   # (recomendado) ejecuta el asistente para .env, instala hooks y deps
```

4. Ejecuta en desarrollo:

```bash
flutter run
```

Preparación rápida tras clonar
-------------------------------

Si acabas de clonar el repositorio, ejecuta lo siguiente para preparar tu entorno e instalar el hook pre-commit que ejecuta el analizador y los tests en cada commit:

```bash
git clone <repo-url>
cd ai_chan
make setup
```

Notas:
- El hook pre-commit ejecuta `flutter analyze` y `flutter test --coverage` en cada commit. Si algún check falla, el commit se aborta.
- Para omitir el hook en un commit puntual (solo cuando sea necesario), usa:

```bash
git commit -m "WIP" --no-verify
```

- Para desinstalar el hook local:

```bash
rm .git/hooks/pre-commit
```


## Compilación por plataforma

- Android: `flutter build apk` / `flutter run` (requiere Android SDK/emulador o dispositivo)
- iOS: requiere macOS y Xcode; firma la app en Xcode para distribución
- Linux (desktop): si ves errores de CMake por cambios de ruta, limpia el build de Linux y regenera:

```bash
rm -rf build/linux/x64/debug
flutter clean
flutter build linux
```

Eso resuelve cachés de CMake que referencian rutas antiguas (por ejemplo `AI-chan` vs `AI_chan`).

## Desarrollo y arquitectura (para desarrolladores)

- Código principal: `lib/`.
- Prompts y construcción del `SystemPrompt`: `lib/services/prompt_builder.dart`.
- Cliente y envío a proveedores de IA: `lib/services/openai_service.dart`.
- Generador de fichas de apariencia y pipeline de imágenes: `lib/services/ia_appearance_generator.dart`.
- Onboarding UI y provider: `lib/screens/onboarding_screen.dart`, `lib/providers/onboarding_provider.dart`.
- Scheduler y detección de promesas/mensajes automáticos: `lib/services/periodic_ia_message_scheduler.dart` y `lib/services/promise_service.dart`.

Consejo: si vas a modificar instrucciones o prompts, evita dejar texto sensible en los logs y considera extraer prompts largos a `docs/PROMPTS.md` (privado o fuera del historial público).

## Logs y depuración

- Durante desarrollo la app escribe archivos JSON en `debug_json_logs/` para permitir inspección de prompts/respuestas y facilitar debugging. Antes de publicar, limpia o anonimiza ese directorio.

## Contribuir

- Abre issues para bugs o propuestas.
- Haz forks y PRs pequeños y documentados.
- Añade tests cuando cambies reglas de negocio o parsing de JSON.

## Licencia

- MIT por defecto. Si prefieres otra licencia, añade un fichero `LICENSE` con la licencia deseada.

## Contacto

- Usa Issues en GitHub para preguntas, propuestas de mejora o reportes de seguridad.

Gracias por tu interés. Si quieres que añada la sección `docs/PROMPTS.md` con los prompts internos (separados del README), dímelo y lo creo como archivo aparte y opcionalmente lo excluyo del repositorio público.
