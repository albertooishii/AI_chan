import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:ai_chan/core/config.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Servicio esqueleto para subir/descargar backups a Google Drive / GCS.
///
/// NOTA: Esta implementación no realiza OAuth. Está pensada como "punto
/// de partida" y ofrece:
/// - Interfaz clara: authenticate(), uploadBackup(), listBackups(), downloadBackup(), deleteBackup()
/// - Implementación HTTP mínima que asume un token de acceso (Bearer) pasado
///   en cada llamada. En producción deberías implementar OAuth2 (flow de
///   dispositivo o iniciar navegador) o usar credenciales de servicio.
class GoogleBackupService {
  /// Nombre fijo del backup en Drive (oculto en appDataFolder)
  static const String backupFileName = 'ai_chan_backup.zip';
  final String? accessToken;
  final Uri driveUploadEndpoint;
  final Uri driveListEndpoint;
  final Uri driveDownloadEndpoint;
  final Uri driveDeleteEndpoint;
  final http.Client httpClient;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Construye un servicio con un `accessToken` opcional. Si no hay token,
  /// métodos que requieren autenticación lanzarán StateError.
  GoogleBackupService({
    required this.accessToken,
    http.Client? httpClient,
    Uri? uploadEndpoint,
    Uri? listEndpoint,
    Uri? downloadEndpoint,
    Uri? deleteEndpoint,
  }) : httpClient = httpClient ?? http.Client(),
       driveUploadEndpoint =
           uploadEndpoint ?? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
       driveListEndpoint = listEndpoint ?? Uri.parse('https://www.googleapis.com/drive/v3/files'),
       driveDownloadEndpoint = downloadEndpoint ?? Uri.parse('https://www.googleapis.com/drive/v3/files'),
       driveDeleteEndpoint = deleteEndpoint ?? Uri.parse('https://www.googleapis.com/drive/v3/files');

  /// Placeholder: en una implementación real arrancaría OAuth y guardaría el token.
  Future<void> authenticate() async {
    if (accessToken == null) {
      throw StateError('No access token provided. Implement OAuth2 or pass an accessToken.');
    }
    // noop for now
  }

  // --- Device-flow helpers (Google OAuth 2.0 device code flow) ---
  /// Start device authorization. Returns a map with keys: device_code, user_code, verification_uri, expires_in, interval
  Future<Map<String, dynamic>> startDeviceAuthorization({
    required String clientId,
    String? clientSecret,
    // Use conservative default scopes for device flow. Some Drive scopes
    // (like drive.appdata) are rejected in device flow for certain clients
    // causing `invalid_scope`. Request identity scopes and a general
    // drive.file scope which is more widely accepted. If appDataFolder
    // access is required, the PKCE/loopback flow will request it.
    List<String> scopes = const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.file'],
  }) async {
    final url = Uri.parse('https://oauth2.googleapis.com/device/code');
    final body = {'client_id': clientId, 'scope': scopes.join(' ')};
    if (clientSecret != null && clientSecret.isNotEmpty) body['client_secret'] = clientSecret;
    final res = await httpClient.post(url, body: body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw HttpException('Device authorization failed: ${res.statusCode} ${res.body}');
  }

  /// Poll token endpoint for device_flow. Returns token map (access_token, refresh_token, expires_in, token_type)
  Future<Map<String, dynamic>> pollForDeviceToken({
    required String clientId,
    String? clientSecret,
    required String deviceCode,
    int interval = 5,
    int maxAttempts = 120,
  }) async {
    final url = Uri.parse('https://oauth2.googleapis.com/token');
    int attempts = 0;
    if (kDebugMode) debugPrint('pollForDeviceToken: starting poll for deviceCode=$deviceCode, interval=$interval');
    while (attempts++ < maxAttempts) {
      final body = {
        'client_id': clientId,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'device_code': deviceCode,
      };
      if (clientSecret != null && clientSecret.isNotEmpty) body['client_secret'] = clientSecret;
      final res = await httpClient.post(url, body: body);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await _persistCredentialsSecure(data);
        if (kDebugMode) debugPrint('pollForDeviceToken: token received for deviceCode=$deviceCode');
        return data;
      } else {
        // Only log detailed polling responses in debug mode.
        if (kDebugMode) debugPrint('pollForDeviceToken: attempt $attempts status=${res.statusCode} body=${res.body}');
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final err = data['error'] as String?;
        if (err == 'authorization_pending') {
          if (kDebugMode) debugPrint('pollForDeviceToken: authorization_pending (attempt $attempts)');
          await Future.delayed(Duration(seconds: interval));
          continue;
        } else if (err == 'slow_down') {
          if (kDebugMode) debugPrint('pollForDeviceToken: slow_down received; increasing interval');
          interval += 5;
          await Future.delayed(Duration(seconds: interval));
          continue;
        } else {
          // Keep unrecoverable error visible in logs in all modes
          debugPrint('pollForDeviceToken: unrecoverable error: $err');
          throw HttpException('Device token polling failed: ${res.statusCode} ${res.body}');
        }
      }
    }
    throw TimeoutException('Device token polling timed out after $maxAttempts attempts');
  }

  /// Refresh an access token using the stored refresh_token.
  Future<Map<String, dynamic>> refreshAccessToken({required String clientId, String? clientSecret}) async {
    final creds = await _loadCredentialsSecure();
    final refresh = creds?['refresh_token'] as String?;
    if (refresh == null) throw StateError('No refresh token available');
    final url = Uri.parse('https://oauth2.googleapis.com/token');
    final res = await httpClient.post(
      url,
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        if (clientSecret != null && clientSecret.isNotEmpty) 'client_secret': clientSecret,
      },
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // Merge refresh_token if Google doesn't return it on refresh
      if (!data.containsKey('refresh_token')) data['refresh_token'] = refresh;
      await _persistCredentialsSecure(data);
      return data;
    }
    throw HttpException('Refresh failed: ${res.statusCode} ${res.body}');
  }

  // Resolve client id/secret from app config based on the current platform.
  /// Public helper: resolve a client ID using a raw candidate and the app Config.
  /// If `rawCid` is empty or placeholder, checks platform-specific keys in `Config`.
  static Future<String> resolveClientId(String rawCid) async {
    var cid = rawCid.trim();
    if (cid.isEmpty || cid.startsWith('YOUR_') || cid == 'YOUR_GOOGLE_CLIENT_ID') {
      try {
        if (kIsWeb) {
          cid = Config.get('GOOGLE_CLIENT_ID_WEB', '');
        } else if (Platform.isAndroid) {
          cid = Config.get('GOOGLE_CLIENT_ID_ANDROID', '');
        } else if (Platform.isIOS) {
          cid = Config.get('GOOGLE_CLIENT_ID_IOS', '');
        } else {
          cid = Config.get('GOOGLE_CLIENT_ID_DESKTOP', '');
        }
      } catch (_) {
        cid = '';
      }
    }
    return cid.trim();
  }

  /// Public helper: resolve a client secret from `Config` for the current platform.
  static Future<String?> resolveClientSecret() async {
    String s = '';
    try {
      if (kIsWeb) {
        s = Config.get('GOOGLE_CLIENT_SECRET_WEB', '');
      } else if (Platform.isAndroid) {
        s = Config.get('GOOGLE_CLIENT_SECRET_ANDROID', '');
      } else if (Platform.isIOS) {
        s = Config.get('GOOGLE_CLIENT_SECRET_IOS', '');
      } else {
        s = Config.get('GOOGLE_CLIENT_SECRET_DESKTOP', '');
      }
    } catch (_) {
      s = '';
    }
    s = s.trim();
    return s.isEmpty ? null : s;
  }

  /// Attempt to refresh stored credentials using config client id/secret.
  /// Returns the refreshed token map on success.
  Future<Map<String, dynamic>> _attemptRefreshUsingConfig() async {
    final creds = await _loadCredentialsSecure();
    final refresh = creds?['refresh_token'] as String?;
    if (refresh == null) throw StateError('No refresh token available to refresh');
    final clientId = await GoogleBackupService.resolveClientId('');
    if (clientId.isEmpty) throw StateError('Client ID not configured; cannot refresh token');
    final clientSecret = await GoogleBackupService.resolveClientSecret();
    return await refreshAccessToken(clientId: clientId, clientSecret: clientSecret);
  }

  /// Exchange an authorization code (from the authorization-code flow) for tokens.
  /// Persists the credentials securely and returns the token map.
  Future<Map<String, dynamic>> exchangeAuthCode({
    required String clientId,
    String? clientSecret,
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    final url = Uri.parse('https://oauth2.googleapis.com/token');
    final body = <String, String>{
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': codeVerifier,
    };
    if (clientSecret != null && clientSecret.isNotEmpty) body['client_secret'] = clientSecret;

    final res = await httpClient.post(url, body: body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _persistCredentialsSecure(data);
      return data;
    }
    throw HttpException('Auth code exchange failed: ${res.statusCode} ${res.body}');
  }

  // --- Simple credential persistence (for desktop/dev). In production use secure storage. ---
  Future<void> _persistCredentialsSecure(Map<String, dynamic> data) async {
    try {
      await _secureStorage.write(key: 'google_credentials', value: jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCredentialsSecure() async {
    try {
      final v = await _secureStorage.read(key: 'google_credentials');
      if (v == null) return null;
      return jsonDecode(v) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Public helper to load the full stored credentials map (access_token,
  /// refresh_token, scope, etc.). Useful for callers that need to inspect
  /// scopes or refresh tokens before deciding to clear credentials.
  Future<Map<String, dynamic>?> loadStoredCredentials() async {
    return await _loadCredentialsSecure();
  }

  /// Devuelve el access_token almacenado si existe, o null.
  Future<String?> loadStoredAccessToken() async {
    final creds = await _loadCredentialsSecure();
    return creds == null ? null : creds['access_token'] as String?;
  }

  /// Si hay un access_token almacenado, intenta recuperar la información
  /// básica del usuario (userinfo). Devuelve el mapa JSON de userinfo si
  /// la token es válida o tras un refresh exitoso, o `null` si no hay token
  /// o la petición falla.
  Future<Map<String, dynamic>?> fetchUserInfoIfTokenValid() async {
    try {
      final token = await loadStoredAccessToken();
      if (token == null) return null;
      final resp = await httpClient.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      // If 401 attempt a refresh using stored refresh token and config
      if (resp.statusCode == 401) {
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            final retryClient = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
            final retryResp = await retryClient.httpClient.get(
              Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
              headers: {'Authorization': 'Bearer $newToken'},
            );
            if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
              return jsonDecode(retryResp.body) as Map<String, dynamic>;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  /// Borra las credenciales almacenadas en el secure storage (si existen).
  /// Útil para forzar que el usuario vuelva a autenticarse.
  Future<void> clearStoredCredentials() async {
    try {
      await _secureStorage.delete(key: 'google_credentials');
      debugPrint('GoogleBackupService: cleared stored credentials');
    } catch (e) {
      debugPrint('GoogleBackupService: failed to clear credentials: $e');
    }
  }

  Map<String, String> _authHeaders() {
    if (accessToken == null) throw StateError('No access token set');
    return {'Authorization': 'Bearer $accessToken'};
  }

  /// Sube un backup ZIP a Google Drive. Devuelve el fileId si fue exitoso.
  /// Este método construye la petición multipart mínima requerida por Drive.
  Future<String> uploadBackup(File zipFile, {String? filename}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final fn = filename ?? backupFileName;

    final meta = {
      'name': fn,
      // Guardar en appDataFolder para mantenerlo oculto
      'parents': ['appDataFolder'],
    };

    final boundary = 'ai_chan_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'multipart/related; boundary=$boundary'};

    final List<int> bodyBytes = [];
    void add(String s) => bodyBytes.addAll(utf8.encode(s));

    add('--$boundary\r\n');
    add('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    add(jsonEncode(meta));
    add('\r\n');
    add('--$boundary\r\n');
    add('Content-Type: application/zip\r\n');
    add('Content-Transfer-Encoding: binary\r\n\r\n');
    bodyBytes.addAll(await zipFile.readAsBytes());
    add('\r\n--$boundary--\r\n');

    // Si ya existe un backup con el mismo nombre en appDataFolder, actualizamos (files.update)
    try {
      final existing = await listBackups();
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;
        final updateUrl = Uri.parse('${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=multipart');
        var resUp = await httpClient.patch(updateUrl, headers: headers, body: bodyBytes);
        if (resUp.statusCode == 401) {
          try {
            final refreshed = await _attemptRefreshUsingConfig();
            final newToken = refreshed['access_token'] as String?;
            if (newToken != null) {
              final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
              return await retrySvc.uploadBackup(zipFile, filename: filename);
            }
          } catch (_) {}
        }
        if (resUp.statusCode >= 200 && resUp.statusCode < 300) {
          final resp = jsonDecode(resUp.body) as Map<String, dynamic>;
          return resp['id'] as String;
        }
        throw HttpException('Upload (update) failed: ${resUp.statusCode} ${resUp.body}');
      }
    } catch (e) {
      // Si la lista falla por permisos, dejamos que la creación inicial lo intente
      debugPrint('GoogleBackupService.uploadBackup: list existing failed: $e');
    }

    var res = await httpClient.post(driveUploadEndpoint, headers: headers, body: bodyBytes);
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.uploadBackup(zipFile, filename: filename);
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final resp = jsonDecode(res.body) as Map<String, dynamic>;
      return resp['id'] as String;
    } else {
      throw HttpException('Upload failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Start a resumable upload and upload the file. Returns fileId on success.
  /// This implements a minimal Drive resumable upload: initiate session then PUT bytes.
  Future<String> uploadBackupResumable(File zipFile, {String? filename}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');

    final fn = filename ?? backupFileName;
    final meta = {
      'name': fn,
      'parents': ['appDataFolder'],
    };

    // Initiate resumable session
    // Si hay un archivo existente, iniciar resumable upload para actualizarlo
    Uri resumableEndpoint;
    try {
      final existing = await listBackups();
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;
        resumableEndpoint = Uri.parse('${driveUploadEndpoint.toString().split('?').first}/$id?uploadType=resumable');
      } else {
        resumableEndpoint = Uri.parse('${driveUploadEndpoint.toString().split('?').first}?uploadType=resumable');
      }
    } catch (_) {
      resumableEndpoint = Uri.parse('${driveUploadEndpoint.toString().split('?').first}?uploadType=resumable');
    }
    final initHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
      'X-Upload-Content-Type': 'application/zip',
    };
    var initRes = await httpClient.post(resumableEndpoint, headers: initHeaders, body: jsonEncode(meta));
    if (!(initRes.statusCode >= 200 && initRes.statusCode < 300)) {
      if (initRes.statusCode == 401) {
        try {
          final refreshed = await _attemptRefreshUsingConfig();
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
            return await retrySvc.uploadBackupResumable(zipFile, filename: filename);
          }
        } catch (_) {}
      }
      throw HttpException('Resumable init failed: ${initRes.statusCode} ${initRes.body}');
    }
    final uploadUrl = initRes.headers['location'] ?? initRes.headers['Location'];
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw StateError('Resumable upload URL not provided by server');
    }

    final bytes = await zipFile.readAsBytes();

    // Single-shot PUT for now. Could be chunked with Content-Range in a loop.
    final putHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/zip',
      'Content-Length': bytes.length.toString(),
      'Content-Range': 'bytes 0-${bytes.length - 1}/${bytes.length}',
    };
    var putRes = await httpClient.put(Uri.parse(uploadUrl), headers: putHeaders, body: bytes);
    if (putRes.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.uploadBackupResumable(zipFile, filename: filename);
        }
      } catch (_) {}
    }
    if (putRes.statusCode >= 200 && putRes.statusCode < 300) {
      final resp = jsonDecode(putRes.body) as Map<String, dynamic>;
      return resp['id'] as String;
    }
    throw HttpException('Resumable upload failed: ${putRes.statusCode} ${putRes.body}');
  }

  /// Lista ficheros en Drive que contengan `ai_chan_backup` en el nombre.
  Future<List<Map<String, dynamic>>> listBackups({int pageSize = 50}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');
    // Buscar en appDataFolder por nombre exacto
    final params = {
      'q': 'name = "$backupFileName"',
      'spaces': 'appDataFolder',
      'pageSize': pageSize.toString(),
      'fields': 'files(id,name,createdTime,size)',
    };
    final q = Uri.parse(driveListEndpoint.toString()).replace(queryParameters: params);
    var res = await httpClient.get(q, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.listBackups(pageSize: pageSize);
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final files = (body['files'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      // Ordenar por createdTime desc y devolver
      files.sort((a, b) {
        final ta = a['createdTime'] as String? ?? '';
        final tb = b['createdTime'] as String? ?? '';
        return tb.compareTo(ta);
      });
      return files;
    } else {
      throw HttpException('List failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Descarga un backup (por fileId) a un archivo local temporal y devuelve el File.
  Future<File> downloadBackup(String fileId, {String? destDir}) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');
    final d = destDir ?? Directory.systemTemp.path;
    final outFile = File('$d/ai_chan_backup_$fileId.zip');
    final url = Uri.parse('${driveDownloadEndpoint.toString()}/$fileId?alt=media');
    var res = await httpClient.get(url, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.downloadBackup(fileId, destDir: destDir);
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await outFile.writeAsBytes(res.bodyBytes, flush: true);
      return outFile;
    } else {
      throw HttpException('Download failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Borra un fichero por fileId en Drive.
  Future<void> deleteBackup(String fileId) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token set');
    final url = Uri.parse('${driveDeleteEndpoint.toString()}/$fileId');
    var res = await httpClient.delete(url, headers: _authHeaders());
    if (res.statusCode == 401) {
      try {
        final refreshed = await _attemptRefreshUsingConfig();
        final newToken = refreshed['access_token'] as String?;
        if (newToken != null) {
          final retrySvc = GoogleBackupService(accessToken: newToken, httpClient: httpClient);
          return await retrySvc.deleteBackup(fileId);
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw HttpException('Delete failed: ${res.statusCode} ${res.body}');
  }
}
