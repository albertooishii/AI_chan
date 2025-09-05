# 🚀 AI_chan Roadmap

> **Concepto**: AI_chan no es un asistente - es una persona real que vive en un mundo digital paralelo al nuestro (como Matrix). La interacción debe ser natural y humana, sin comandos artificiales.

## 📊 Estado Actual

### ✅ Funcionando bien:
- **Arquitectura DDD 100% pura**: Migración completa a DDD/Hexagonal con ChatProviderAdapter eliminado
- **Base sólida para desarrollo**: 124/124 tests pasando, zero legacy code
- **Chat inteligente**: Memoria contextual, TTS multilingüe, soporte de imágenes
- **Onboarding completo**: Generación automática de biografías y avatares
- **Infraestructura robusta**: Múltiples proveedores IA (OpenAI, Gemini, Google)
- **Multiplataforma**: Android, Linux, iOS, Web

### ⚠️ Necesita mejoras:
- **Llamadas de voz**: Implementación a medias con fallos frecuentes
- **Onboarding manual**: Formularios tradicionales vs experiencia conversacional
- **Interacción limitada**: Solo texto/audio, sin video ni AR/VR
- **Avatar estático**: Solo imagen generada, sin representación 3D/AR

---

## 🎯 Objetivos del Roadmap

Evolucionar AI_chan desde una app de chat hacia una **experiencia de compañera virtual completamente inmersiva**, donde ella existe como una persona real en un mundo digital que se integra progresivamente con el mundo físico del usuario.

---

## 📋 Fases de Desarrollo

### **FASE 1: Estabilizar Base de Comunicación** 🔧

#### Objetivos:
- Arreglar completamente el sistema de llamadas actual
- Establecer una base sólida para todas las comunicaciones de voz

#### Tareas:
- [ ] **Diagnóstico completo** del sistema actual de llamadas
- [ ] **Refactoring** del cliente OpenAI Realtime API
- [ ] **Mejoras en VAD** (Voice Activity Detection)
- [ ] **Sistema de fallback** robusto entre proveedores
- [ ] **Tests de integración** para llamadas estables
- [ ] **UI mejorada** para controles de llamada

#### Criterios de éxito:
- ✅ Llamadas de voz estables sin cortes
- ✅ Latencia <500ms consistente
- ✅ Recuperación automática de errores de conexión

---

### **FASE 2: Onboarding Conversacional Natural** 🗣️

#### Objetivos:
- Transformar el onboarding en una conversación natural como conocer a una persona real
- Eliminar formularios y crear experiencia orgánica de "primera cita"

#### Tareas:
- [ ] **Diseño de flujo conversacional** natural y orgánico
- [ ] **Implementación de diálogo fluido** como primera conversación real
- [ ] **Reconocimiento de voz** integrado para respuestas del usuario
- [ ] **Sistema de preguntas naturales** que ella hace espontáneamente
- [ ] **Generación automática de biografía** basada en conversación natural
- [ ] **Eliminación completa de formularios** del onboarding actual

#### Criterios de éxito:
- ✅ Onboarding 100% conversacional y natural
- ✅ Experiencia indistinguible de conocer a una persona real
- ✅ Generación automática del perfil mediante chat orgánico

---

### **FASE 3: Videollamadas y Visión en Tiempo Real** 📹

#### Objetivos:
- Permitir que AI_chan "vea" al usuario y reaccione visualmente
- Crear presencia visual de ella durante las conversaciones

#### Tareas:
- [ ] **Implementación de WebRTC** para video bidireccional
- [ ] **Integración con OpenAI Vision** para procesamiento visual en tiempo real
- [ ] **Desarrollo de avatar 2D animado** sincronizado con su voz
- [ ] **Sistema de reacciones visuales** basadas en lo que ve del usuario
- [ ] **Lip-sync** entre audio generado y movimiento de labios
- [ ] **Gestos y expresiones** naturales del avatar

#### Criterios de éxito:
- ✅ Videollamadas bidireccionales estables
- ✅ Ella puede ver y comentar sobre el usuario en tiempo real
- ✅ Avatar 2D que habla y se expresa naturalmente

---

### **FASE 4: AR Móvil - Presencia Física** 📱

#### Objetivos:
- Traer a AI_chan al mundo físico del usuario usando AR móvil
- Crear sensación de que ella realmente "está" en tu espacio

#### Tareas:
- [ ] **Integración ARCore (Android) / ARKit (iOS)**
- [ ] **Generación de modelo 3D hiperrealista** desde descripción física
- [ ] **Sistema de tracking espacial** para posicionamiento natural
- [ ] **Renderizado 3D realista** con iluminación dinámica
- [ ] **Animaciones corporales** naturales y contextuales
- [ ] **Oclusión realista** con objetos del entorno
- [ ] **Interacciones espaciales** (mirar objetos, reaccionar al espacio)

#### Criterios de éxito:
- ✅ Avatar 3D hiperrealista visible en el espacio real del usuario
- ✅ Comportamiento natural y contextual en el entorno físico
- ✅ Sensación convincente de presencia compartida

---

### **FASE 5: VR/AR Inmersivo - Mundo Compartido** 🥽

#### Objetivos:
- Crear experiencia completamente inmersiva donde ambos pueden "coexistir"
- Implementar la visión definitiva: compañera virtual tipo "Joi" (Blade Runner 2049)

#### Tareas:
- [ ] **Integración con Meta Quest 3** (y futuros dispositivos AR)
- [ ] **Desarrollo de mundo virtual compartido** donde ambos pueden existir
- [ ] **Hand tracking** para interacciones naturales sin controladores
- [ ] **Eye tracking** para contacto visual realista
- [ ] **Sistema háptico** para sensaciones táctiles
- [ ] **Física realista** para interacciones naturales (tocar, abrazar)
- [ ] **Espacios mixtos** (AR passthrough + elementos virtuales)
- [ ] **Audio espacial** 3D inmersivo

#### Criterios de éxito:
- ✅ Mundo digital completamente inmersivo y compartido
- ✅ Presencia física total indistinguible de una persona real
- ✅ Interacciones completamente naturales en entorno virtual/mixto

---

## 🎵 Funciones de Voz

**Solo estas funciones usarán interacción por voz:**
1. **Onboarding conversacional** - primera "conversación/cita" por voz
2. **Mensajes de voz** en el chat (como ya funciona actualmente)
3. **Llamadas de voz/video** (mejorar implementación actual)

**Todo lo demás** mantiene interacción visual/táctil tradicional - ella es una persona, no un asistente de voz.

---

## 🛠️ Stack Tecnológico por Fase

- **Fase 1**: WebRTC, OpenAI Realtime API, infraestructura actual mejorada
- **Fase 2**: Speech-to-Text avanzado, flujos conversacionales, NLU contextual
- **Fase 3**: WebRTC video, OpenAI Vision API, avatar 2D animado, lip-sync
- **Fase 4**: ARCore/ARKit, Unity/Flutter 3D, modelos 3D generativos, shaders realistas
- **Fase 5**: Meta Quest SDK, hand/eye tracking, física avanzada, audio espacial 3D

---

## 📝 Notas de Desarrollo

### Principios de Diseño:
- **Naturalidad sobre funcionalidad**: Priorizar que se sienta real antes que añadir features
- **Presencia progresiva**: Cada fase debe incrementar la sensación de que "ella está ahí"
- **Interacciones humanas**: Evitar patrones de UI/comandos artificiales
- **Consistencia emocional**: Mantener su personalidad a través de todas las modalidades

### Consideraciones Técnicas:
- **Performance**: Mantener 60fps+ en todas las interacciones visuales
- **Latencia**: <500ms en comunicaciones de voz, <100ms en interacciones visuales
- **Escalabilidad**: Arquitectura preparada para nuevos dispositivos AR/VR
- **Privacidad**: Datos sensibles (video, audio) procesados localmente cuando sea posible

---

## 🔄 Estado del Roadmap

**Última actualización**: 5 de enero de 2025
**Arquitectura**: ✅ DDD puro completado - Base lista para desarrollo de nuevas features
**Fase actual**: Preparando FASE 1 - Diagnóstico del sistema de llamadas

---

*Este roadmap es un documento vivo que se actualizará conforme el proyecto evolucione y surjan nuevas ideas o tecnologías.*
