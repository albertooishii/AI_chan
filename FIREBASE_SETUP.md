# 🔧 Firebase Setup Guide

Esta guía te ayudará a configurar Firebase para el proyecto AI-chan.

## 📋 Pre-requisitos

1. Cuenta de Google/Firebase
2. Proyecto Firebase creado
3. Android Studio instalado (para SHA-1)

## 🚀 Configuración paso a paso

### 1. Crear proyecto Firebase
1. Ve a [Firebase Console](https://console.firebase.google.com)
2. Crea un nuevo proyecto o usa uno existente
3. Habilita los servicios necesarios:
   - Authentication (Google Sign-In)
   - Cloud Storage
   - (Otros servicios según necesidades)

### 2. Configurar Android App
1. En Firebase Console, agrega una app Android
2. Usar package name: `com.albertooishii.ai_chan`
3. Obtén el SHA-1 certificate fingerprint:
   ```bash
   cd android && ./gradlew signingReport
   ```
4. Descarga `google-services.json`

### 3. Instalar archivos de configuración
```bash
# Copiar los archivos de configuración
cp /path/to/downloaded/google-services.json ./google-services.json
cp /path/to/downloaded/google-services.json ./android/app/google-services.json
```

### 4. Configurar variables de entorno
Crear archivo `.env` en la raíz:
```env
# Google OAuth Credentials
GOOGLE_CLIENT_ID_WEB=tu-client-id-web.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET_WEB=tu-client-secret-web
GOOGLE_CLIENT_ID_ANDROID=tu-client-id-android.apps.googleusercontent.com
GOOGLE_REDIRECT_URI=com.albertooishii.ai_chan:/oauthredirect
```

## 🔒 Seguridad

### ⚠️ IMPORTANTE: No subir credenciales a Git

Los siguientes archivos **NUNCA** deben subirse al repositorio:
- `google-services.json`
- `android/app/google-services.json`  
- `.env`

Estos archivos están incluidos en `.gitignore` para tu seguridad.

### ✅ Archivos incluidos en el repositorio:
- `google-services.example.json` (plantilla sin datos reales)
- `android/app/google-services.example.json` (plantilla sin datos reales)

## 🧪 Para desarrollo/testing

Si necesitas un setup de testing/desarrollo:

1. Copia las plantillas:
   ```bash
   cp google-services.example.json google-services.json
   cp android/app/google-services.example.json android/app/google-services.json
   ```

2. Reemplaza los valores con tus credenciales reales
3. Configura el `.env` con tus keys

## 🔍 Verificación

Para verificar que tu configuración es correcta:

```bash
flutter doctor -v
flutter analyze
flutter test
```

## 🚨 En caso de problemas

1. **Auth errors**: Verifica que el SHA-1 certificate esté configurado correctamente
2. **Package name mismatch**: Asegúrate que coincida `com.albertooishii.ai_chan`
3. **Credenciales no válidas**: Regenera y vuelve a descargar `google-services.json`

---

¿Necesitas ayuda? Revisa la [documentación oficial de Firebase](https://firebase.google.com/docs) o abre un issue.
