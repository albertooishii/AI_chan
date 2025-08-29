// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform, HttpServer, InternetAddress;
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart' show showAppDialog, showAppSnackBar;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show MissingPluginException, Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:ai_chan/main.dart' show navigatorKey;

/// Dialog minimalista: flujo único "Vincular → Detectar backup → Restaurar".
class GoogleDriveBackupDialog extends StatefulWidget {
  final String clientId;
  final Future<String?> Function()? requestBackupJson;
  final Future<void> Function(String json)? onImportedJson;
  final Future<void> Function({String? email, String? avatarUrl, String? name, bool linked})? onAccountInfoUpdated;
  final VoidCallback? onClearAccountInfo;
  final bool disableAutoRestore;

  const GoogleDriveBackupDialog({
    super.key,
    this.clientId = 'YOUR_GOOGLE_CLIENT_ID',
    this.requestBackupJson,
    this.onImportedJson,
    this.onAccountInfoUpdated,
    this.onClearAccountInfo,
    this.disableAutoRestore = false,
  });

  @override
  State<GoogleDriveBackupDialog> createState() => _GoogleDriveBackupDialogState();
}

class _GoogleDriveBackupDialogState extends State<GoogleDriveBackupDialog> {
  String? _status;
  GoogleBackupService? _service;
  Map<String, dynamic>? _latestBackup;
  String? _email;
  String? _avatarUrl;
  String? _name;
  bool _working = false;
  bool _hasChatProvider = false;
  bool _insufficientScope = false;
  final FlutterSecureStorage _localSecure = const FlutterSecureStorage();
  String? _lastAuthUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLinkedAndCheck());
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<String> _resolveClientId(String rawCid) async => await GoogleBackupService.resolveClientId(rawCid);
  Future<String?> _resolveClientSecret() async => await GoogleBackupService.resolveClientSecret();

  Future<void> _ensureLinkedAndCheck() async {
    if (!mounted) return;
    _safeSetState(() {
      _status = 'Comprobando estado de vinculación...';
      _working = true;
    });

    try {
      _hasChatProvider = (widget.requestBackupJson != null || widget.onImportedJson != null);

      final candidateCid = await _resolveClientId(widget.clientId);
      final svc = GoogleBackupService(accessToken: null);
      final token = await svc.loadStoredAccessToken();

      if (token != null) {
        if (!_hasChatProvider) {
          try {
            await svc.clearStoredCredentials();
          } catch (_) {}
          _service = null;
        } else {
          _service = GoogleBackupService(accessToken: token);
          try {
            await _fetchAccountInfo(token, attemptRefresh: true);
          } catch (_) {}
          _safeSetState(() => _status = 'Cuenta ya vinculada');
          await _checkForBackupAndMaybeRestore();
          return;
        }
      }

      _safeSetState(() => _status = 'Iniciando vinculación...');

      if (kIsWeb) {
        await _pkceOobFlow(candidateCid);
        return;
      }

      try {
        await _pkceOobFlow(candidateCid);
        return;
      } catch (e) {
        final msg = e.toString();
        if (kDebugMode) debugPrint('device-flow via PKCE/OOB failed: $msg');
        if (msg.contains('invalid_scope')) {
          try {
            await GoogleBackupService(accessToken: null).clearStoredCredentials();
          } catch (_) {}
          _insufficientScope = true;
          _safeSetState(() {
            _status = 'Permisos insuficientes. Reintenta y se han borrado las credenciales locales.';
            _working = false;
          });
          return;
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('ensureLinkedAndCheck error: $e');
      _safeSetState(() {
        _status = 'Error vinculación: $e';
        _working = false;
      });
    }
  }

  Future<void> _pkceOobFlow(String clientId) async {
    _safeSetState(() => _status = 'Iniciando AppAuth...');
    final isDesktop = !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
    HttpServer? loopbackServer;
    String? redirectForAppAuth;
    if (isDesktop) {
      try {
        loopbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final port = loopbackServer.port;
        redirectForAppAuth = 'http://127.0.0.1:$port/';
      } catch (e) {
        debugPrint('Failed to bind loopback server for AppAuth: $e');
        loopbackServer = null;
        redirectForAppAuth = null;
      }
    }

    try {
      final svcApp = GoogleBackupService(accessToken: null);
      final tokenMap = await svcApp.authenticateWithAppAuth(clientId: clientId, redirectUri: redirectForAppAuth);
      if (tokenMap['access_token'] != null) {
        _service = GoogleBackupService(accessToken: tokenMap['access_token'] as String?);
        unawaited(_fetchAccountInfo(tokenMap['access_token'] as String?));
        _safeSetState(() => _status = 'Vinculación completada (AppAuth)');
        await _checkForBackupAndMaybeRestore();
        return;
      }
    } catch (e) {
      debugPrint('AppAuth attempt failed: $e');
      _safeSetState(() {
        _status = 'Se abrió la web de autorización; espera a que completes el proceso en el navegador.';
        _working = true;
      });
      if (e is MissingPluginException || e.toString().contains('MissingPluginException')) {
        if (isDesktop) {
          try {
            await _manualPkceFallback(clientId, redirectForAppAuth, existingServer: loopbackServer);
            return;
          } catch (e2) {
            debugPrint('Manual PKCE fallback failed: $e2');
          }
        }
        _safeSetState(
          () => _status = 'AppAuth no disponible en esta plataforma; usando fallback PKCE si está disponible.',
        );
        return;
      }

      // Show a simple status so the user knows the browser was opened and
      // the app is waiting for the loopback redirect.
      _safeSetState(() {
        _status = 'Se abrió la web de autorización; espera a que completes el proceso en el navegador.';
        _working = true;
      });
      return;
    }
  }

  Future<void> _manualPkceFallback(String clientId, String? redirectUri, {HttpServer? existingServer}) async {
    final redirect = (redirectUri != null && redirectUri.isNotEmpty) ? redirectUri : 'http://127.0.0.1:0/';
    final rnd = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final codeVerifier = base64UrlEncode(rnd).replaceAll('=', '');
    final bytes = sha256.convert(utf8.encode(codeVerifier)).bytes;
    final codeChallenge = base64UrlEncode(bytes).replaceAll('=', '');

    final authUri = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email profile https://www.googleapis.com/auth/drive.appdata',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'prompt': 'consent',
        'access_type': 'offline',
      },
    );

    Uri finalRedirect = Uri.parse(redirect);
    HttpServer? server = existingServer;
    if (server == null) {
      if (redirect.contains(':0')) {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        finalRedirect = Uri.parse('http://127.0.0.1:${server.port}/');
      } else {
        try {
          final port = finalRedirect.port;
          if (port != 0) server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        } catch (_) {
          server = null;
        }
      }
    }

    final authUriWithRedirect = authUri.replace(
      queryParameters: {...authUri.queryParameters, 'redirect_uri': finalRedirect.toString()},
    );
    // Keep the last built auth URL available so the user can copy it if needed.
    _safeSetState(() => _lastAuthUrl = authUriWithRedirect.toString());
    String? code;

    // Open the authorization URL directly in the system browser.
    final opened = await _openUrlPreferNewWindow(authUriWithRedirect);
    if (!opened) {
      final manual = await showAppDialog<bool>(
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Abrir navegador'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No se pudo abrir el navegador automáticamente. Copia el enlace y ábrelo manualmente en tu navegador.',
              ),
              const SizedBox(height: 8),
              SelectableText(authUriWithRedirect.toString(), maxLines: 5),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: authUriWithRedirect.toString()));
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Copiar enlace'),
            ),
          ],
        ),
      );
      if (manual != true) throw StateError('Usuario canceló operación de abrir navegador');
    }

    // linkToCopy removed (manual paste flow disabled)

    // If we have a loopback server, listen in background and auto-close the dialog
    Completer<void>? serverCompleter;
    if (server != null) {
      serverCompleter = Completer<void>();

      // Start background listener: capture the first incoming request (the OAuth redirect),
      // extract the authorization code and serve the packaged success page that attempts to
      // notify the opener and close the browser window.
      () async {
        final srv = server!; // server is non-null here
        final sc = serverCompleter!;
        try {
          final req = await srv.first.timeout(const Duration(minutes: 5));
          final q = req.uri.queryParameters;
          code = q['code'];
          try {
            req.response.statusCode = 200;
            req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
            try {
              final successHtml = await rootBundle.loadString('assets/oauth_success.html');
              req.response.write(successHtml);
              await req.response.close();
            } catch (e) {
              // If the success asset is missing, abort to allow manual fallback.
              try {
                req.response.statusCode = 500;
                await req.response.close();
              } catch (_) {}
              if (kDebugMode) debugPrint('Missing oauth_success.html asset: $e');
              if (!serverCompleter.isCompleted) serverCompleter.complete();
              return;
            }
          } catch (_) {}
        } catch (e) {
          if (kDebugMode) debugPrint('Loopback listener error: $e');
        } finally {
          try {
            if (existingServer == null) await srv.close(force: true);
          } catch (_) {}
          if (!sc.isCompleted) sc.complete();
        }
      }();
    }

    // No UX dialog: wait silently for the loopback listener to capture the code.
    if (serverCompleter != null) {
      try {
        await serverCompleter.future.timeout(const Duration(minutes: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('Loopback wait timed out: $e');
      }
    } else {
      // Manual paste flow removed: cannot continue without loopback capture.
      throw StateError('No loopback server available; manual paste flow removed');
    }

    // If still no code after waiting, fallback to manual paste
    if (code == null) throw StateError('Authorization code not received');

    final clientSecret = await GoogleBackupService.resolveClientSecret();

    final tokenBody = {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': finalRedirect.toString(),
      'client_id': clientId,
      'code_verifier': codeVerifier,
    };
    if (clientSecret != null && clientSecret.isNotEmpty) tokenBody['client_secret'] = clientSecret;

    final tokenResp = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: tokenBody,
    );
    if (tokenResp.statusCode < 200 || tokenResp.statusCode >= 300)
      throw StateError('Token exchange failed: ${tokenResp.statusCode} ${tokenResp.body}');
    final data = jsonDecode(tokenResp.body) as Map<String, dynamic>;
    final tokenMap = <String, dynamic>{
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
      'expires_in': data['expires_in'] ?? 0,
      'token_type': data['token_type'],
      'scope': data['scope'] ?? '',
    };

    await _localSecure.write(key: 'google_credentials', value: jsonEncode(tokenMap));
    _service = GoogleBackupService(accessToken: tokenMap['access_token'] as String?);
    unawaited(_fetchAccountInfo(tokenMap['access_token'] as String?));
    _safeSetState(() => _status = 'Vinculación completada (PKCE fallback)');
    await _checkForBackupAndMaybeRestore();
  }

  // Authorization wait dialog removed: flow is automatic and waits silently for loopback capture

  Future<bool> _openUrlPreferNewWindow(Uri url) async {
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('openUrl failed: $e');
    }
    return false;
  }

  // _extractCodeFromUrlOrCode removed (manual paste flow disabled)

  // Manual paste dialog removed by request.

  Future<void> _checkForBackupAndMaybeRestore() async {
    if (!mounted) return;
    _safeSetState(() => _status = 'Comprobando copia de seguridad en Google Drive...');
    try {
      final svc = _service ?? GoogleBackupService(accessToken: null);
      final files = await svc.listBackups();
      if (!mounted) return;
      if (files.isEmpty) {
        _latestBackup = null;
        if (!_hasChatProvider) {
          _safeSetState(() {
            _status = 'Cuenta vinculada correctamente.';
            _working = false;
          });
          return;
        }
        _safeSetState(() {
          _status = 'No hay copias de seguridad en Google Drive';
          _working = false;
        });
        return;
      }

      files.sort((a, b) {
        final ta = a['createdTime'] as String? ?? '';
        final tb = b['createdTime'] as String? ?? '';
        return tb.compareTo(ta);
      });
      _latestBackup = files.first;
      String human = '';
      try {
        final sizeStr = _latestBackup!['size']?.toString();
        if (sizeStr != null) {
          final sz = int.tryParse(sizeStr) ?? 0;
          human = _humanFileSize(sz);
        }
        final ct = _latestBackup!['createdTime'] as String?;
        if (ct != null && ct.isNotEmpty) {
          final parsed = DateTime.tryParse(ct);
          if (parsed != null) {
            final local = parsed.toLocal();
            final date =
                '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
            final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
            final formatted = '$date $time';
            human = human.isNotEmpty ? '$human • $formatted' : formatted;
          }
        }
      } catch (_) {}
      final statusText = human.isNotEmpty ? 'Copia de seguridad disponible: $human' : 'Copia de seguridad disponible';
      _safeSetState(() => _status = statusText);
      _safeSetState(() => _working = false);
      return;
    } catch (e) {
      final msg = e.toString();
      debugPrint('checkForBackup error: $msg');
      if (msg.contains('invalid_scope')) {
        try {
          await GoogleBackupService(accessToken: null).clearStoredCredentials();
        } catch (_) {}
        _insufficientScope = true;
        _safeSetState(() {
          _status = 'Permisos insuficientes al acceder a Drive. Se han borrado las credenciales locales.';
          _working = false;
        });
        return;
      }
      if (msg.contains('The granted scopes do not give access') || msg.contains('insufficientScopes')) {
        debugPrint(
          'Detected insufficient scopes for requested spaces; verifying stored credentials before prompting re-link',
        );
        try {
          final svc = GoogleBackupService(accessToken: null);
          final creds = await svc.loadStoredCredentials();
          final storedScope = (creds?['scope'] as String?) ?? '';
          if (kDebugMode) debugPrint('Stored credential scopes: $storedScope');
          if (storedScope.contains('drive.appdata') && creds != null && creds['refresh_token'] != null) {
            try {
              final clientId = await _resolveClientId(widget.clientId);
              final clientSecret = await _resolveClientSecret();
              final svc = GoogleBackupService(accessToken: null);
              final refreshed = await svc.refreshAccessToken(clientId: clientId, clientSecret: clientSecret);
              if (kDebugMode) debugPrint('Refreshed tokens after detecting appData in stored scope: ${refreshed.keys}');
              final newToken = refreshed['access_token'] as String?;
              if (newToken != null) {
                _service = GoogleBackupService(accessToken: newToken);
                unawaited(_fetchAccountInfo(newToken, attemptRefresh: false));
                return;
              }
            } catch (e) {
              debugPrint('userinfo refresh failed: $e');
            }
          }
        } catch (e) {
          debugPrint('checkForBackup error: $e');
        }
      }
    }
  }

  Future<void> _fetchAccountInfo(String? accessToken, {bool attemptRefresh = false}) async {
    if (accessToken == null) return;
    try {
      final resp = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        _safeSetState(() {
          _email = data['email'] as String?;
          _avatarUrl = data['picture'] as String?;
          _name = data['name'] as String?;
        });
        try {
          if (widget.onAccountInfoUpdated != null) {
            await widget.onAccountInfoUpdated!(email: _email, avatarUrl: _avatarUrl, name: _name, linked: true);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('onAccountInfoUpdated propagation failed: $e');
        }
        return;
      }
      if (resp.statusCode == 401 && attemptRefresh) {
        try {
          final clientId = await _resolveClientId(widget.clientId);
          final clientSecret = await _resolveClientSecret();
          final svc = GoogleBackupService(accessToken: null);
          final refreshed = await svc.refreshAccessToken(clientId: clientId, clientSecret: clientSecret);
          final newToken = refreshed['access_token'] as String?;
          if (newToken != null) {
            _service = GoogleBackupService(accessToken: newToken);
            unawaited(_fetchAccountInfo(newToken, attemptRefresh: false));
            return;
          }
        } catch (e) {
          debugPrint('userinfo refresh failed: $e');
        }
      }
      debugPrint('userinfo request failed: ${resp.statusCode} ${resp.body}');
    } catch (e) {
      debugPrint('userinfo request error: $e');
    }
  }

  Future<void> _createBackupNow() async {
    if (_service == null) return;
    if (widget.requestBackupJson == null) {
      _safeSetState(() {
        _status = 'Para crear una copia en Google Drive, proporciona un callback requestBackupJson.';
      });
      return;
    }

    _safeSetState(() => _status = 'Creando copia de seguridad local...');
    try {
      final jsonStr = await widget.requestBackupJson!();
      if (jsonStr == null) throw Exception('requestBackupJson devolvió null');
      final file = await BackupService.createLocalBackup(jsonStr: jsonStr);
      _safeSetState(() => _status = 'Subiendo copia de seguridad a Google Drive...');
      await _service!.uploadBackup(file);
      _safeSetState(() => _status = 'Copia subida correctamente');
    } catch (e) {
      debugPrint('createBackupNow error: $e');
      _safeSetState(() => _status = 'Error creando/subiendo copia de seguridad: $e');
    }
  }

  Future<void> _restoreLatestNow() async {
    if (_latestBackup == null) return;
    _safeSetState(() => _status = 'Descargando copia de seguridad...');
    final svc = _service ?? GoogleBackupService(accessToken: null);
    try {
      final backupId = _latestBackup!['id'] as String;
      final file = await svc.downloadBackup(backupId);
      _safeSetState(() => _status = 'Restaurando copia de seguridad...');
      final extractedJson = await BackupService.restoreAndExtractJson(file);
      if (widget.onImportedJson != null) {
        try {
          await widget.onImportedJson!(extractedJson);
          try {
            if (!mounted) return;
            final navState = navigatorKey.currentState;
            if (navState != null && navState.canPop()) navState.pop(true);
          } catch (_) {}
          return;
        } catch (e) {
          debugPrint('onImportedJson failed: $e');
          _safeSetState(() {
            _status = 'Error importando copia de seguridad en el callback del llamador';
            _working = false;
          });
          return;
        }
      }
      try {
        final navState = navigatorKey.currentState;
        if (navState != null && navState.canPop()) navState.pop({'restoredJson': extractedJson});
      } catch (_) {}
      return;
    } catch (e) {
      debugPrint('restoreLatest failed: $e');
      _safeSetState(() => _status = 'Error restaurando copia de seguridad: $e');
      _safeSetState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _service != null;
    return SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                const Icon(Icons.add_to_drive, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Copia de seguridad en Google Drive',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  // Allow closing even while a background auth flow is in progress so
                  // the user can interrupt and dismiss the dialog.
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_service != null) ...[
            Row(
              children: [
                if (_avatarUrl != null)
                  CircleAvatar(backgroundImage: NetworkImage(_avatarUrl!))
                else
                  const Icon(Icons.account_circle, size: 40, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_name != null)
                        Text(
                          _name!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      Text(_email ?? 'Cuenta vinculada', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (_status != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(_status!, style: const TextStyle(color: Colors.white70)),
              ),
            ),
          const SizedBox(height: 12),

          if (!linked) ...[
            Text('Estado: No vinculada', style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_insufficientScope) ...[
                  Tooltip(
                    message: 'Pulsa para volver a vincular y conceder acceso a Google Drive',
                    child: ElevatedButton(
                      onPressed: _working
                          ? null
                          : () async {
                              try {
                                await GoogleBackupService(accessToken: null).clearStoredCredentials();
                              } catch (_) {}
                              setState(() => _insufficientScope = false);
                              await _ensureLinkedAndCheck();
                            },
                      child: const Text('Re-vincular (conceder acceso a Google Drive)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // The main link button is hidden in this UI variant; keep it in code
                // for quick re-enable but not shown to users.
                Visibility(
                  visible: false,
                  child: ElevatedButton(
                    onPressed: _working ? null : _ensureLinkedAndCheck,
                    child: const Text('Vincular cuenta de Google'),
                  ),
                ),
                const SizedBox(width: 8),
                // Copy link button: useful when the browser didn't open automatically.
                // Copiar URL / Abrir página: botones para el caso en que el navegador no se abra
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar URL'),
                  onPressed: () async {
                    if (_lastAuthUrl == null) {
                      showAppSnackBar('No hay enlace de autorización disponible aún. Pulsa "Vincular" para empezar.');
                      return;
                    }
                    try {
                      await Clipboard.setData(ClipboardData(text: _lastAuthUrl!));
                      showAppSnackBar('Enlace de autorización copiado al portapapeles.');
                    } catch (e) {
                      debugPrint('Failed to copy auth url: $e');
                      showAppSnackBar('No se pudo copiar el enlace. Intenta manualmente.', isError: true);
                    }
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir página'),
                  onPressed: () async {
                    if (_lastAuthUrl == null) {
                      showAppSnackBar('No hay enlace de autorización disponible aún. Pulsa "Vincular" para empezar.');
                      return;
                    }
                    try {
                      final opened = await _openUrlPreferNewWindow(Uri.parse(_lastAuthUrl!));
                      if (!opened) {
                        showAppSnackBar('No se pudo abrir el navegador automáticamente. Usa "Copiar URL" para abrir manualmente.');
                      }
                    } catch (e) {
                      debugPrint('Failed to open auth url: $e');
                      showAppSnackBar('Error al intentar abrir la página. Usa "Copiar URL" para abrir manualmente.', isError: true);
                    }
                  },
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 0),
            const SizedBox(height: 8),
            Row(
              children: [
                Row(
                  children: [
                    if (_latestBackup != null)
                      ElevatedButton(
                        onPressed: _working ? null : _restoreLatestNow,
                        child: const Text('Restaurar ahora'),
                      ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (ctx) {
                        if (widget.requestBackupJson != null)
                          return ElevatedButton(
                            onPressed: _working ? null : _createBackupNow,
                            child: const Text('Hacer copia ahora'),
                          );
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _working
                      ? null
                      : () async {
                          final confirm = await showAppDialog<bool>(
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Colors.black,
                              title: const Text('Desvincular cuenta', style: TextStyle(color: Colors.cyanAccent)),
                              content: const Text(
                                '¿Seguro que quieres desvincular la cuenta de Google? Se borrarán las credenciales locales.',
                                style: TextStyle(color: Colors.white),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Desvincular', style: TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            setState(() {
                              _working = true;
                              _status = 'Desvinculando cuenta...';
                            });
                            try {
                              await GoogleBackupService(accessToken: null).clearStoredCredentials();
                            } catch (_) {}
                            _safeSetState(() {
                              _service = null;
                              _email = null;
                              _avatarUrl = null;
                              _name = null;
                              _latestBackup = null;
                              _insufficientScope = false;
                              _status = 'Cuenta desvinculada';
                            });
                            try {
                              if (widget.onClearAccountInfo != null) widget.onClearAccountInfo!();
                            } catch (_) {}
                            try {
                              final navState = navigatorKey.currentState;
                              if (navState != null && navState.canPop()) navState.pop(true);
                            } catch (_) {}
                          }
                        },
                  child: const Text('Desvincular', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _humanFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    i = i.clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, i);
    String s;
    if (size >= 100 || size.truncateToDouble() == size)
      s = size.toStringAsFixed(0);
    else if (size >= 10)
      s = size.toStringAsFixed(1);
    else
      s = size.toStringAsFixed(2);
    return '$s ${suffixes[i]}';
  }
}

// Note: inline HTML fallbacks removed. The flow now requires packaged
// assets `assets/oauth_start.html` and `assets/oauth_success.html`. If those
// assets are missing the loopback flow will abort and the manual paste dialog
// will be used instead.
