Integración de Google Backup (Drive / GCS)

Resumen
-------
Este documento explica el andamiaje mínimo de integración añadido en `lib/shared/services/google_backup_service.dart`.

Objetivos
---------
- Proporcionar una interfaz simple y testeable para subir/descargar/eliminar backups en Google Drive.
- Mantener OAuth fuera del núcleo por ahora; ofrecer notas claras sobre cómo conectar tokens OAuth.

Cómo funciona (andamiaje actual)
-------------------------------
- `GoogleBackupService` es un envoltorio ligero sobre la API REST de Drive.
- Espera que se le pase un token de acceso (token OAuth2 Bearer) al construirlo.
- Métodos: `authenticate()` (marcador de posición), `uploadBackup(File)`, `listBackups()`, `downloadBackup(id)`, `deleteBackup(id)`.

Notas sobre OAuth
-----------------
Debes obtener un token OAuth2 con el scope `https://www.googleapis.com/auth/drive.appdata`.
Flujos recomendados:
- Aplicación de escritorio/móvil: usar el device code flow de OAuth2 o abrir un navegador para el consentimiento del usuario. Guarda los tokens de forma segura.
- Lado servidor o CI: usa una cuenta de servicio y Google Cloud Storage si procede.

Dónde obtener el `client_id`:
- Crea un OAuth 2.0 Client ID en la consola de Google Cloud: https://console.cloud.google.com/apis/credentials
- Documentación del device code flow (OAuth2): https://developers.google.com/identity/protocols/oauth2/limited-input-device

Client IDs por plataforma
-------------------------
Es recomendable crear un Client ID separado por plataforma y guardarlos en variables de entorno distintas. A continuación las recomendaciones y tipos a usar en la consola de Google Cloud:

- Desktop (escritorio): crea un OAuth Client ID de tipo "Desktop" o "Other".
	- Variable .env recomendada: `GOOGLE_CLIENT_ID_DESKTOP`.
	- Flujo sugerido: device code flow (no requiere redirect URIs) o abrir un navegador para consentimiento y luego intercambiar el código.

- Android: crea un OAuth Client ID de tipo "Android" y proporciona el package name y el SHA-1 de la keystore.
	- Variable .env recomendada: `GOOGLE_CLIENT_ID_ANDROID`.
	- Flujo sugerido: OAuth basado en navegador (custom tabs) o Google Sign-In; requiere configurar redirect URIs si usas flujos web.
	- Cómo obtener SHA-1 (ejemplo):
		```bash
		keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
		```

- Web: crea un OAuth Client ID de tipo "Web application" y añade los Orígenes JavaScript autorizados y Redirect URIs (p. ej. http://localhost:8080).
	- Variable .env recomendada: `GOOGLE_CLIENT_ID_WEB`.
	- Flujo sugerido: OAuth por redirect/popup (redirect URI debe coincidir exactamente).

Variables de entorno y ejemplos
--------------------------------
Añade estas entradas en tu `.env` (vacías si prefieres rellenarlas manualmente):

```
GOOGLE_CLIENT_ID_DESKTOP=
GOOGLE_CLIENT_ID_ANDROID=
GOOGLE_CLIENT_ID_WEB=
```

Y en `.env.example` usa placeholders descriptivos.

Seleccionar el client_id en tiempo de ejecución (snippet Dart)
---------------------------------------------------------
Usa `flutter_dotenv` o la estrategia que prefieras para leer `.env`. Ejemplo mínimo para elegir el client id según la plataforma:

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

String getPlatformClientId() {
	final env = DotEnv().env; // o dotenv.env si usas flutter_dotenv
	if (kIsWeb) return env['GOOGLE_CLIENT_ID_WEB'] ?? '';
	if (Platform.isAndroid) return env['GOOGLE_CLIENT_ID_ANDROID'] ?? '';
	// Desktop: Linux/Mac/Windows
	return env['GOOGLE_CLIENT_ID_DESKTOP'] ?? '';
}
```

Notas por plataforma
--------------------
- Desktop: el device code flow es el más sencillo para apps sin navegador embebido; muestra el código al usuario y pídeles que lo peguen en https://www.google.com/device
- Android: para una experiencia nativa considera integrar Google Sign-In o usar custom tabs para el flujo OAuth; asegúrate de configurar el SHA-1 correcto.
- Web: asegúrate de que los orígenes y redirects configurados en la consola coincidan exactamente con los usados por tu app local/producción.

Ejemplo rápido
--------------
1) Adquiere un token (fuera del alcance de este documento) y colócalo en la configuración o en el entorno de la app.
2) Subir:

```dart
final service = GoogleBackupService(accessToken: '<TOKEN>');
final jsonStr = await provider.exportAllToJson();
final file = await BackupService.createLocalBackup(jsonStr: jsonStr);
final id = await service.uploadBackup(file);
print('Uploaded file id: $id');
```

Seguridad
--------
- No hardcodees tokens en el código fuente ni los comitees.
- Para producción, implementa manejo adecuado de refresh tokens.

Alternativas
------------
- Google Cloud Storage con signed URLs o cuentas de servicio para backups gestionados por servidor.
- Usar librerías de terceros para el flujo OAuth (por ejemplo, `oauth2`, `googleapis_auth`).

Siguientes pasos
----------------
- Implementar un flujo OAuth adecuado (device code o basado en navegador) y refresco de tokens.
- Añadir UI para permitir al usuario vincular su cuenta de Google y gestionar backups.
- Añadir tests unitarios con respuestas HTTP mockeadas.
