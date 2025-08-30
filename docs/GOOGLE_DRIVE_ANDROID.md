# Google Drive Integration para Android

## Resumen de cambios

Se ha implementado una solución completa para la vinculación de Google Drive en Android que incluye:

1. **Chooser nativo de Google**: Usa `google_sign_in` para mostrar el selector nativo de cuentas
2. **Refresh token**: Obtiene y maneja correctamente refresh tokens para acceso a largo plazo
3. **Experiencia de usuario mejorada**: Interfaz más intuitiva con feedback visual
4. **Manejo robusto de errores**: Mejor diagnostico y recuperación de errores
5. **Prevención de chooser doble**: Optimización para evitar que aparezca dos veces el selector

## Problema del chooser doble - SOLUCIONADO

### ¿Por qué aparecía dos veces?
El problema se debía a que había **dos flujos de autenticación separados**:
1. **Primera llamada**: `linkAccount()` intentaba obtener refresh_token llamando `_attemptServerAuthCodeExchange()`
2. **Segunda llamada**: El flujo principal llamaba a `_signInUsingNativeGoogleSignIn()`

Ambas terminaban ejecutando `GoogleSignInMobileAdapter.signIn()` con `signOut()` automático.

### ✅ Solución implementada:
1. **Eliminación de llamada duplicada**: Removido `_attemptServerAuthCodeExchange()` de la lógica de `linkAccount()`
2. **Sign-out condicional**: El adaptador ahora solo hace `signOut()` cuando `forceAccountChooser=true`
3. **Sign-in silencioso**: Agregado método `signInSilently()` para obtener tokens sin mostrar chooser
4. **Flujo optimizado**: Si hay tokens sin refresh_token, se intenta sign-in silencioso antes de sign-in interactivo

### Nuevos parámetros:
- `GoogleSignInMobileAdapter.signIn(forceAccountChooser: bool)`: Controla si mostrar chooser
- `GoogleSignInMobileAdapter.signInSilently()`: Sign-in sin UI cuando es posible

## Archivos nuevos/modificados

### Archivos nuevos:
- `lib/shared/services/google_signin_adapter_mobile.dart`: Adaptador nativo para Android/iOS
- `lib/shared/widgets/google_drive_connector.dart`: Widget para manejar conexión con UI
- `lib/shared/widgets/google_drive_demo_screen.dart`: Pantalla de demo/testing

### Archivos modificados:
- `lib/shared/services/google_backup_service.dart`: Actualizado para usar el nuevo adaptador nativo
- `pubspec.yaml`: Agregado `google_sign_in: ^6.2.1`
- `android/app/src/main/AndroidManifest.xml`: Agregado queries para Google Services

## Configuración requerida

### 1. Archivo .env
Asegúrate de que tienes configurados estos valores:
```env
GOOGLE_CLIENT_ID_WEB=tu-web-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET_WEB=tu-web-client-secret
GOOGLE_CLIENT_ID_ANDROID=tu-android-client-id.apps.googleusercontent.com
```

### 2. Google Cloud Console
1. **Cliente Android OAuth**: Configurado con el package name y SHA-1 de tu app
2. **Cliente Web OAuth**: Necesario para intercambio de server auth code
3. **APIs habilitadas**: Google Drive API y Google+ API
4. **Pantalla de consentimiento**: Configurada con los scopes necesarios

### 3. google-services.json
Archivo debe estar presente en `android/app/` con la configuración correcta del proyecto Firebase.

## Uso básico

### Integrar en tu app existente:
```dart
import 'package:ai_chan/shared/widgets/google_drive_connector.dart';

// Envolver tu widget principal
GoogleDriveConnector(
  onConnectionChanged: (isConnected, userInfo) {
    // Manejar cambios de estado de conexión
    print('Connected: $isConnected');
    if (userInfo != null) {
      print('User: ${userInfo['email']}');
    }
  },
  child: YourMainWidget(),
)
```

### Uso programático:
```dart
import 'package:ai_chan/shared/services/google_backup_service.dart';

// Crear servicio
final service = GoogleBackupService(accessToken: null);

// Vincular cuenta (muestra chooser nativo)
final tokenMap = await service.linkAccount(forceUseGoogleSignIn: true);

// Verificar si hay tokens válidos
final userInfo = await service.fetchUserInfoIfTokenValid();

// Subir un backup
final fileId = await service.uploadBackup(myZipFile);

// Listar backups
final backups = await service.listBackups();

// Refrescar token
final newTokens = await service.refreshAccessToken(
  clientId: 'tu-client-id',
  clientSecret: 'tu-client-secret'
);
```

## Demo screen

Para probar la funcionalidad, puedes usar la pantalla de demo:
```dart
import 'package:ai_chan/shared/widgets/google_drive_demo_screen.dart';

// Navegar a la demo
Navigator.push(
  context, 
  MaterialPageRoute(builder: (context) => GoogleDriveDemoScreen())
);
```

## Cómo funciona

### 1. Flujo de autenticación
1. Usuario toca "Conectar"
2. Se muestra el chooser nativo de Google con todas las cuentas disponibles
3. Usuario selecciona cuenta y da permisos
4. Se obtienen access_token, id_token y server_auth_code
5. El server_auth_code se intercambia por refresh_token usando el cliente web
6. Todos los tokens se almacenan de forma segura

### 2. Manejo de refresh token
- El refresh token se obtiene mediante el intercambio de server auth code
- Se almacena de forma segura usando `flutter_secure_storage`
- Automáticamente se refresca cuando el access token expira
- Fallback a Firebase token si el OAuth refresh falla

### 3. Experiencia de usuario
- Chooser nativo: Muestra todas las cuentas Google del dispositivo
- Feedback visual: Indicadores de carga, estado de conexión
- Manejo de errores: Mensajes claros y opciones de retry
- Persistencia: La sesión se mantiene entre reinicios de la app

## Troubleshooting

### Error: "access_blocked"
- Verifica que el SHA-1 certificate esté registrado en Google Cloud Console
- Asegúrate de usar el cliente OAuth correcto (Android client para la app)
- Revisa que la pantalla de consentimiento esté configurada correctamente

### Error: "invalid_client"
- Verifica que `GOOGLE_CLIENT_ID_WEB` y `GOOGLE_CLIENT_SECRET_WEB` sean correctos
- Asegúrate de que el cliente web OAuth esté habilitado

### No aparece chooser nativo
- Verifica que `google-services.json` esté configurado correctamente
- Revisa que Google Play Services esté instalado en el dispositivo
- Asegúrate de estar usando `forceUseGoogleSignIn: true` en Android

### Refresh token no se obtiene
- Verifica que estés usando `forceCodeForRefreshToken: true`
- Asegúrate de que el cliente web OAuth tenga los permisos correctos
- Revisa que `GOOGLE_CLIENT_SECRET_WEB` esté configurado

## Logs útiles

Para debugging, busca estos tags en los logs:
- `GoogleSignIn`: Logs del adaptador nativo
- `GoogleBackup`: Logs del servicio principal  
- `GoogleDrive`: Logs del widget connector
- `GoogleDriveDemo`: Logs de la pantalla demo

## Próximos pasos

1. Implementar upload de backups reales (crear ZIP de datos)
2. Agregar sincronización automática de backups
3. Implementar download e importación de backups
4. Optimizar manejo de grandes archivos con uploads resumibles
5. Agregar compresión de backups

## Beneficios de esta implementación

✅ **Chooser nativo**: Mejor UX con selector de cuentas nativo de Android
✅ **Refresh token**: Acceso de largo plazo sin reautenticación constante  
✅ **Manejo robusto de errores**: Mejor diagnostico y recuperación
✅ **Interfaz intuitiva**: Widgets reutilizables para fácil integración
✅ **Testing**: Pantalla demo para verificar funcionamiento
✅ **Logs detallados**: Fácil debugging y monitoreo
✅ **Compatibilidad**: Funciona con la arquitectura existente
