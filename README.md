# AI-chan

AI-chan es una "novia virtual": una aplicación experimental que crea una compañera conversacional personalizada. La app combina chat con memoria contextual, llamadas de voz en tiempo real con prosodia natural, y generación de avatar a partir de una ficha de apariencia creada por IA. Está pensada para experimentación, investigación y uso personal responsable — no para suplantación, abuso ni usos ilegales.

## 🏗️ Arquitectura

Este proyecto implementa **DDD (Domain-Driven Design) + Hexagonal Architecture** con 4 bounded contexts:

- **Chat**: Gestión de conversaciones, mensajes y servicios TTS
- **Onboarding**: Creación y configuración de perfiles  
- **Call**: Servicios de llamadas de voz (WebRTC/OpenAI Realtime)
- **Shared**: Kernel compartido entre contextos

### Estructura del Proyecto
```
lib/
├── chat/
│   ├── domain/          # Interfaces y modelos de dominio
│   ├── application/     # Casos de uso y providers
│   ├── infrastructure/  # Adaptadores e implementaciones
│   └── presentation/    # UI y widgets
├── onboarding/         # Mismo patrón DDD
├── call/               # Llamadas de voz en tiempo real
├── core/               # DI, configuración, interfaces compartidas
└── shared/             # Servicios y utilidades compartidas
```

### Quality Metrics ✅
- **Tests**: 124/124 pasando (100%) - 62 archivos de test
- **Arquitectura**: 5/5 tests DDD pasando - 0 violaciones
- **Flutter analyze**: Clean - 0 errores/warnings
- **Versión Flutter**: 3.35.1
- **SDK Dart**: ^3.8.1

## CI

Status: ![CI](https://github.com/albertooishii/AI_chan/actions/workflows/ci.yml/badge.svg)

**Testing note**: Para salida más predecible y menos entrelazada (especialmente útil en CI), ejecuta: `flutter test -j 1 -r expanded` o usa la tarea VS Code `flutter-test-j1`.

Principales características

- **Chat inteligente con contexto**: La IA mantiene memoria contextual y usa una ficha de perfil para dar continuidad natural a la relación.
- **Llamadas de voz en tiempo real**: Sistema de llamadas con OpenAI Realtime API y Google TTS/STT, con detección automática de idiomas y prosodia natural.
- **Generación de avatar personalizado**: Creación automática de ficha de apariencia (JSON) y generación de imagen realista a partir de ella.
- **Onboarding guiado inteligente**: Proceso inicial para crear el perfil de la IA usando generación automática de biografías y personalidades compatibles.
- **Arquitectura limpia**: DDD + Hexagonal Architecture con 100% cobertura de tests y 0 violaciones arquitecturales.

## 🎯 Funcionalidades principales

### 💬 Sistema de Chat Avanzado
- **Memoria contextual inteligente**: Sistema de resúmenes automáticos que mantiene el contexto de conversaciones largas
- **TTS multilingüe**: Síntesis de voz con detección automática de idioma y voces nativas
- **Procesamiento de mensajes**: Soporte para texto, audio y imágenes en una misma conversación

### 📞 Llamadas de Voz en Tiempo Real
- **OpenAI Realtime API**: Llamadas bidireccionales de baja latencia
- **Google Cloud Speech**: TTS/STT con voces premium y detección automática de idioma  
- **VAD (Voice Activity Detection)**: Detección inteligente de cuando el usuario habla
- **Estrategias adaptativas**: Fallback automático entre diferentes proveedores

### 🎨 Generación de Avatar IA
- **Generación automática de apariencia**: La IA crea una descripción física detallada basada en la biografía
- **Renderizado realista**: Generación de imagen usando modelos de IA avanzados
- **Persistencia inteligente**: Compresión y almacenamiento optimizado de imágenes

### ⚙️ Onboarding Inteligente
- **Generación automática de biografías**: La IA crea historias compatibles y realistas
- **Configuración de personalidad**: Sistema de traits y características que influyen en el comportamiento
- **Validación y consistencia**: Verificación automática de coherencia entre datos

## 📋 Onboarding - Datos recopilados

El flujo de onboarding crea la ficha `onboarding_data` que alimenta los prompts y generadores:

**Datos del usuario:**
- País y configuración de idioma  
- Nombre y fecha de nacimiento
- Preferencias de contenido y límites

**Datos de la IA:**
- Nombre y país de origen
- Biografía y personalidad (generada automáticamente)
- Apariencia física (descripción JSON detallada)
- Avatar visual (imagen generada por IA)
- Historia de cómo se conocieron (puede auto-generarse)

**Persistencia:**
- Todo se guarda en `SharedPreferences` bajo la clave `onboarding_data`
- Formato JSON exportable/importable para backup
- Compatible con el sistema de backup a Google Drive (cuando está configurado)

## 🔐 Privacidad y seguridad

- **🔑 Claves API**: Nunca subas claves a repositorios públicos. Usa `.env` (está en `.gitignore`)
- **📁 Debug logs**: Revisa `debug_json_logs/` y borra datos sensibles antes de publicar
- **⚖️ Contenido generado**: La app puede generar contenido íntimo/imágenes. Respeta leyes locales, edad legal y políticas de IA
- **🛡️ Tests seguros**: Los tests usan fakes/mocks - no hacen llamadas reales a APIs

## 📋 Onboarding - Datos recopilados

El flujo de onboarding crea el perfil que alimenta la IA:

**Datos del usuario:**
- País y configuración de idioma  
- Nombre y fecha de nacimiento
- Preferencias de contenido

**Datos de la IA:**
- Nombre y país de origen
- Biografía y personalidad (generada automáticamente)
- Apariencia física (descripción JSON)
- Avatar visual (imagen generada)

Todo se guarda en `SharedPreferences` y puede exportarse/importarse como JSON.

## 🚀 Estado del proyecto

### Últimas mejoras implementadas
- ✅ **Refactoring arquitectural completo** de "voice" → "call" para mayor claridad
- ✅ **Eliminación de compatibilidad hacia atrás** del sistema de audio antiguo  
- ✅ **Arquitectura DDD limpia** con 0 violaciones y 100% cobertura de tests
- ✅ **TTS multilingüe mejorado** con detección automática de idioma usando Google TTS
- ✅ **124 tests completos** cubriendo todos los bounded contexts

### Tecnologías y frameworks
- **🎯 Flutter 3.35.1** - UI multiplataforma con hot reload automático
- **🧠 OpenAI** (GPT-4, DALL-E, Realtime API) - IA conversacional y generación
- **🌟 Google Gemini 2.5 Flash** - Modelos de texto avanzados de Google
- **☁️ Google Cloud** (Speech-to-Text, Text-to-Speech) - Servicios de voz premium
- **🏗️ DDD + Hexagonal** - Arquitectura limpia y mantenible
- **🔊 Grok** - Soporte para modelo alternativo de texto
- **🎵 Audio avanzado**: audioplayers, speech_to_text, flutter_tts, record
- **📱 Integración nativa**: Android Intent, permisos, file_picker
- **🔐 Seguridad**: flutter_secure_storage, crypto, OAuth con Google/Firebase
- **💾 Persistencia**: shared_preferences, path_provider con backup automático

### Compatibilidad de plataformas
- ✅ **Android** - APK y Android App Bundle
- ✅ **Linux Desktop** - Ejecutable nativo  
- ✅ **iOS** - Requiere macOS y Xcode para compilación
- ✅ **Web** - Funcionamiento básico (limitaciones de WebRTC)

*Este repositorio es experimental y está en desarrollo activo. Respeta el consentimiento, la edad legal y las políticas de los proveedores de IA.*

## 🔧 Variables de entorno (`.env`)

Usa el archivo `.env.example` incluido en la raíz como referencia y renómbralo a `.env` con tus claves privadas:

```env
# --- Claves de API (obligatorias) ---
GEMINI_API_KEY=PUT_YOUR_GEMINI_KEY_HERE
GROK_API_KEY=PUT_YOUR_GROK_KEY_HERE
GEMINI_API_KEY_FALLBACK=PUT_YOUR_FALLBACK_KEY_HERE
OPENAI_API_KEY=PUT_YOUR_OPENAI_KEY_HERE
GOOGLE_CLOUD_API_KEY=PUT_YOUR_GOOGLE_CLOUD_KEY_HERE

# --- Configuración OAuth Google (opcional) ---
GOOGLE_CLIENT_ID_DESKTOP=PUT_YOUR_GOOGLE_CLIENT_ID_DESKTOP
GOOGLE_CLIENT_ID_ANDROID=PUT_YOUR_GOOGLE_CLIENT_ID_ANDROID
GOOGLE_CLIENT_ID_WEB=PUT_YOUR_GOOGLE_CLIENT_ID_WEB

# --- Configuración de Audio/Voz ---
AUDIO_PROVIDER=gemini                 # openai | gemini
AUDIO_TTS_MODE=google                 # google | local
OPENAI_VOICE_NAME=marin                # alloy|ash|ballad|coral|echo|sage|shimmer|verse|cedar|marin
GOOGLE_VOICE_NAME=es-ES-Wavenet-F     # Voz premium de Google TTS
PREFERRED_AUDIO_FORMAT=mp3            # mp3 | m4a | wav

# --- Modelos de IA ---
DEFAULT_TEXT_MODEL=gemini-2.5-flash
DEFAULT_IMAGE_MODEL=gpt-4.1-mini
OPENAI_REALTIME_MODEL=gpt-realtime
GOOGLE_REALTIME_MODEL=gemini-2.5-flash

# --- Modelos específicos OpenAI ---
OPENAI_TTS_MODEL=gpt-4o-mini-tts       # Modelo para síntesis de voz
OPENAI_STT_MODEL=gpt-4o-mini-transcribe # Modelo para transcripción

# --- Configuración avanzada ---
DEBUG_MODE=full                       # full|basic|minimal|off (controla logs, JSON debug, y opciones UI)
SUMMARY_BLOCK_SIZE=32                 # Mensajes por bloque de resumen
APP_NAME=AI-チャン                     # Nombre de la aplicación
```

### Notas importantes:
- 🔒 **El archivo `.env` está en `.gitignore`**: nunca subas tus claves al repositorio
- 🔄 **Fallback automático**: Si `GEMINI_API_KEY` falla (cuota/permisos), la app usa `GEMINI_API_KEY_FALLBACK`
- 🎵 **Voces OpenAI**: alloy, ash, ballad, coral, echo, sage, shimmer, verse, cedar, marin
- 🗣️ **Voces Google**: Consulta [Google TTS Voices](https://cloud.google.com/text-to-speech/docs/voices) para opciones
- ☁️ **Google Cloud**: necesario para TTS/STT premium con detección automática de idioma
- 🔊 **Audio Provider**: `gemini` usa Google TTS/STT, `openai` usa OpenAI Realtime
- ✨ **Nuevas voces**: `cedar` y `marin` están disponibles exclusivamente con el modelo `gpt-realtime`

## 🔒 Hooks pre-commit y CI/CD

El proyecto incluye hooks automáticos para mantener la calidad:

```bash
# Instalar hooks (incluido en make install)
make install-hooks
# O directamente:
./scripts/install-hooks.sh

# El hook ejecuta automáticamente en cada commit:
flutter analyze    # Análisis estático
flutter test       # Tests completos con cobertura
```

**Control de hooks:**
```bash
git commit -m "WIP" --no-verify  # Omitir hook puntualmente
rm .git/hooks/pre-commit         # Desinstalar hook local
```

### 🧪 Testing y quality metrics

**Cobertura completa:**
- ✅ **124/124 tests pasando** (100% success rate)
- ✅ **62 archivos de test** distribuidos por bounded context
- ✅ **5/5 tests de arquitectura** (DDD compliance)
- ✅ **0 violaciones** de arquitectura hexagonal
- ✅ **0 warnings** en flutter analyze

**Tests por categoría:**
```bash
# Tests unitarios por bounded context
flutter test test/chat/       # Tests del dominio chat
flutter test test/call/       # Tests del dominio call (antes voice)
flutter test test/onboarding/ # Tests de onboarding

# Tests de arquitectura y reglas
flutter test test/architecture/

# Tests de integración completos
flutter test test/integration/

# Tests de seguridad y otros
flutter test test/security/
flutter test test/shared/
```

## 🚀 Instalación y ejecución

### Requisitos
- **Flutter 3.35.1** (canal `stable`) 
- **Dart SDK 3.8.1+**
- SDKs nativos de las plataformas objetivo
- Claves de API (OpenAI, Gemini, Google Cloud)

### Instalación rápida

1. **Clona el repositorio:**
```bash
git clone <tu-repo>.git
cd ai_chan
```

2. **Configuración automática (recomendado):**
```bash
make install  # Instala deps, configura .env y hooks pre-commit
# O también: make setup
```

3. **O configuración manual:**
```bash
flutter pub get
cp .env.example .env
# Edita .env con tus claves reales
```

4. **Ejecuta en desarrollo:**
```bash
make run             # Hot reload automático con inotify
make start           # Alias para run
flutter run -d linux # Flutter estándar
```

### 🧪 Testing y quality assurance

```bash
make test            # Tests completos con cobertura
make analyze         # Análisis estático (flutter analyze)  
make build           # Alias para analyze
flutter test -j 1 -r expanded  # Tests con salida expandida
```


## Compilación por plataforma

### Android
```bash
flutter build apk           # Debug APK
flutter build appbundle     # Release App Bundle para Play Store
flutter run                 # En emulador o dispositivo conectado
```
Requiere: Android SDK, emulador configurado o dispositivo físico

### Linux Desktop
```bash
flutter build linux         # Ejecutable nativo
flutter run -d linux        # Ejecutar directamente
make run                    # Con hot reload automático
```

**Solución de problemas CMake:**
```bash
# Si ves errores de CMake después de cambios de estructura:
rm -rf build/linux/x64/debug
flutter clean
flutter build linux
```

### iOS (Solo en macOS)
```bash
flutter build ios
```
Requiere: Xcode, configuración de firma para distribución

### Web
```bash
flutter build web
flutter run -d chrome
```
⚠️ **Limitaciones**: WebRTC puede tener funcionalidad reducida

### Windows
```bash
flutter build windows
```
Requiere: Visual Studio con herramientas C++

## 🛠️ Desarrollo y arquitectura

### Arquitectura DDD + Hexagonal

El proyecto sigue estrictamente **Domain-Driven Design** con **Arquitectura Hexagonal**:

```
Bounded Context: Chat
├── Domain Layer    # Entidades, Value Objects, Interfaces
├── Application     # Use Cases, Services, Providers  
├── Infrastructure  # Adapters, Repositories, External APIs
└── Presentation    # UI, Widgets, Controllers

Bounded Context: Call
├── Domain Layer    # Call, CallMessage, IRealtimeClient
├── Application     # CallController, CallProvider
├── Infrastructure  # OpenAIRealtimeCallClient, GoogleCallClient
└── Presentation    # CallScreen, CallControls
```

### Archivos clave por funcionalidad

**🗣️ Sistema de llamadas:**
- `lib/call/domain/entities/call.dart` - Entidad principal de llamada
- `lib/call/application/controllers/call_controller.dart` - Lógica de control de llamadas
- `lib/call/infrastructure/adapters/openai_realtime_call_client.dart` - Cliente OpenAI Realtime

**💬 Chat y TTS:**
- `lib/chat/application/services/tts_service.dart` - Síntesis de voz con detección automática de idioma
- `lib/chat/infrastructure/adapters/language_resolver_service.dart` - Resolución de idiomas para TTS
- `lib/chat/application/providers/chat_provider.dart` - Estado principal del chat

**🎨 Generación de contenido:**
- `lib/core/services/ia_appearance_generator.dart` - Generación de apariencia física
- `lib/core/services/ia_avatar_generator.dart` - Creación de imágenes de avatar
- `lib/onboarding/infrastructure/adapters/profile_adapter.dart` - Generación de biografías

**⚙️ Configuración y DI:**
- `lib/core/config.dart` - Configuración centralizada desde `.env`
- `lib/core/di.dart` - Inyección de dependencias
- `lib/core/runtime_factory.dart` - Factory de servicios IA (OpenAI, Gemini)

## 📞 Contacto y soporte

- **🐛 Issues**: Reporta bugs o solicitudes en [GitHub Issues](https://github.com/albertooishii/AI_chan/issues)
- **🔒 Seguridad**: Para vulnerabilidades, abre un issue marcado como "security"  
- **💡 Ideas**: Sugiere mejoras a través de issues con la etiqueta "enhancement"
- **📚 Documentación adicional**: 
  - [`FIREBASE_SETUP.md`](FIREBASE_SETUP.md) - Configuración de Firebase y OAuth
  - [`.env.example`](.env.example) - Plantilla de configuración completa

### 📁 Estructura de archivos importantes

```
ai_chan/
├── .env.example              # Plantilla de configuración
├── FIREBASE_SETUP.md         # Guía de configuración Firebase
├── Makefile                  # Comandos de desarrollo automatizados
├── scripts/
│   ├── setup_env.sh         # Script interactivo de configuración
│   ├── install-hooks.sh     # Instalación de git hooks
│   ├── run_dev.sh           # Hot reload automático con inotify
│   └── pre-commit           # Hook de calidad automático
└── debug_json_logs/         # Logs de desarrollo (limpiar antes de publicar)
```

## 📄 Licencia

MIT - Ver archivo [LICENSE](LICENSE) para detalles completos.

---

<p align="center">
  <strong>AI-chan</strong> - Experimental Virtual Companion<br>
  Built with ❤️ using Flutter, OpenAI, and Google AI
</p>
