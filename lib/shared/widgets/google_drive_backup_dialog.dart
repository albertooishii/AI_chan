// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform, HttpServer, InternetAddress;
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart' show showAppDialog;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:ai_chan/main.dart' show navigatorKey;

/// Dialog minimalista: flujo único "Vincular → Detectar backup → Restaurar".
class GoogleDriveBackupDialog extends StatefulWidget {
  final String clientId;

  // Optional callbacks to decouple the dialog from any specific provider.
  // If `requestBackupJson` is provided, the dialog will call it to obtain
  // the JSON string to create a local backup for upload.
  final Future<String?> Function()? requestBackupJson;

  // If provided the dialog will call `onImportedJson` with the extracted
  // backup JSON when restoring; otherwise it will pop {'restoredJson': json}
  // so the caller can import it.
  final Future<void> Function(String json)? onImportedJson;

  // Optional callback to propagate account info (email/avatar/name/linked)
  // to the caller (e.g., a provider) when fetched from Google.
  final Future<void> Function({String? email, String? avatarUrl, String? name, bool linked})? onAccountInfoUpdated;

  // Optional callback invoked when the dialog unlinks/clears account info.
  final VoidCallback? onClearAccountInfo;

  /// When true, the dialog will not perform an automatic restore even if a backup is found.
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
  final _rng = Random.secure();
  String? _status;
  GoogleBackupService? _service;
  Map<String, dynamic>? _latestBackup;
  String? _email;
  String? _avatarUrl;
  String? _name;
  bool _working = false;
  bool _hasChatProvider = false;
  bool _insufficientScope = false;
  bool _scopeUpgradeInProgress = false;

  int _randomByte() => _rng.nextInt(256);

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLinkedAndCheck());
  }

  Future<String> _resolveClientId(String rawCid) async {
    return await GoogleBackupService.resolveClientId(rawCid);
  }

  Future<String?> _resolveClientSecret() async {
    return await GoogleBackupService.resolveClientSecret();
  }

  Future<void> _ensureLinkedAndCheck() async {
    if (!mounted) return;
    _safeSetState(() {
      _status = 'Comprobando estado de vinculación...';
      _working = true;
    });

    try {
      // Consider the dialog able to perform provider-like actions when the
      // caller supplied relevant callbacks (export/import/account propagation).
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
          // Validate token and attempt refresh if invalid/expired.
          try {
            await _fetchAccountInfo(token, attemptRefresh: true);
          } catch (_) {}
          _safeSetState(() => _status = 'Cuenta ya vinculada');
          await _checkForBackupAndMaybeRestore();
          return;
        }
      }

      _safeSetState(() => _status = 'Iniciando vinculación...');
      // On web we prefer PKCE loopback/OOB. On other platforms (desktop, mobile)
      // try the Device Authorization Flow first (which yields a verification URL
      // suitable for QR scanning). If the OAuth client rejects device flow,
      // we will fall back to PKCE/OOB below.
      if (kIsWeb) {
        await _pkceOobFlow(candidateCid);
        return;
      }

      try {
        // Delegate to the PKCE/OOB helper which already prefers device-flow
        // for QR-based UX and starts polling in background when appropriate.
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
    // If already linked, skip showing PKCE/OOB UI to avoid reopening dialogs.
    // However, if we're performing a scope upgrade, allow the PKCE flow even
    // when `_service` is set so we can request additional scopes.
    if (_service != null && !_scopeUpgradeInProgress) {
      if (kDebugMode) {
        debugPrint('pkceOobFlow: already linked and no scope upgrade in progress, skipping PKCE/OOB flow');
      }
      return;
    }

    _safeSetState(() => _status = 'Abriendo navegador para autorización...');
    var codeVerifier = base64UrlEncode(List<int>.generate(64, (i) => _randomByte()));
    var bytes = sha256.convert(utf8.encode(codeVerifier)).bytes;
    var codeChallenge = base64UrlEncode(bytes).replaceAll('=', '');

    HttpServer? server;
    int? port;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to bind loopback server: $e');
      server = null;
    }

    final redirectUri = (port != null) ? 'http://127.0.0.1:$port/' : 'urn:ietf:wg:oauth:2.0:oob';
    var authUrl = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        // Request identity scopes so we can show email/avatar in the UI
        'scope': 'openid email profile https://www.googleapis.com/auth/drive.appdata',
        'access_type': 'offline',
        'prompt': 'consent select_account',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    // OOB variant for QR/paste flows: when scanned on another device it will
    // display a code the user can paste back into this app. The loopback
    // `authUrl` is still used for same-device browser openings.
    var oobAuthUrl = authUrl.replace(
      queryParameters: {...authUrl.queryParameters, 'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob'},
    );

    // Declare qrUri in outer scope. It will prefer device verification URL
    // when available, otherwise fallback to OOB.
    String? qrUri;

    // Prepare the OOB string and pick initial qrUri (prefer device flow if available)
    var verificationUriOob = oobAuthUrl.toString();

    // Also try Device Authorization Flow verification URL for the QR if the
    // OAuth client supports it. This is more reliable for cross-device
    // scanning because it leads to a page that shows a user code to paste.
    Map<String, dynamic>? deviceInfo;
    String? deviceVerificationUrl;
    try {
      // Start device authorization once and keep the returned device info so
      // we can poll with the same device_code. Prefer the "verification_uri_complete"
      // field when available because it already includes the user code and
      // scanning it usually avoids "invalid_request" errors.
      final candidateClientSecret = await _resolveClientSecret();
      final svc = GoogleBackupService(accessToken: null);
      // First attempt: ask for drive.appdata. Some OAuth clients may reject
      // this scope for device flow; if so, fall back to a more widely
      // supported drive.file scope.
      try {
        if (kDebugMode) debugPrint('Attempting device authorization requesting drive.appdata');
        deviceInfo = await svc.startDeviceAuthorization(
          clientId: clientId,
          clientSecret: candidateClientSecret,
          scopes: const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.appdata'],
        );
      } catch (e) {
        final msg = e.toString();
        if (kDebugMode) debugPrint('Device authorization with drive.appdata failed: $msg');
        if (msg.contains('invalid_scope') || msg.contains('invalid_request')) {
          try {
            if (kDebugMode) debugPrint('Falling back to device authorization requesting drive.file');
            deviceInfo = await svc.startDeviceAuthorization(
              clientId: clientId,
              clientSecret: candidateClientSecret,
              scopes: const ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.file'],
            );
          } catch (e2) {
            debugPrint('Fallback device authorization also failed: $e2');
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      // Prefer the provided complete verification URI. If it's missing but
      // we have a verification URI and a user_code, construct a URL that
      // includes the user_code so scanning the QR will not require manual entry.
      String? verification = deviceInfo['verification_uri_complete'] as String?;
      if (verification == null) {
        final v = (deviceInfo['verification_url'] ?? deviceInfo['verification_uri']) as String?;
        final uc = deviceInfo['user_code'] as String?;
        if (v != null && uc != null) {
          verification = '$v?user_code=${Uri.encodeComponent(uc)}';
        }
      }
      deviceVerificationUrl = verification;
    } catch (e) {
      // ignore - client may not support device flow
      deviceInfo = null;
      deviceVerificationUrl = null;
    }

    // If the OAuth client supports the Device Authorization Flow, prefer
    // using its verification URL as the QR target. Instead of showing a
    // separate modal for the device flow (which caused multiple dialogs on
    // desktop), set the QR target and start polling in background. The
    // existing two-column dialog will be the visible UI on desktop.
    if (deviceVerificationUrl != null) {
      try {
        final svcDevice = GoogleBackupService(accessToken: null);
        final actualDeviceInfo = deviceInfo;
        if (actualDeviceInfo != null) {
          _safeSetState(() {
            _status = 'Esperando autorización (flujo dispositivo)...';
            qrUri = deviceVerificationUrl;
          });

          // Start polling in background; when it succeeds, finish linking.
          try {
            final deviceCode = actualDeviceInfo['device_code'] as String;
            final deviceInterval = actualDeviceInfo['interval'] ?? 5;
            final candidateClientSecret = await _resolveClientSecret();
            if (kDebugMode) {
              debugPrint('Starting background device poll for device_code=$deviceCode, interval=$deviceInterval');
            }
            unawaited(
              svcDevice
                  .pollForDeviceToken(
                    clientId: clientId,
                    clientSecret: candidateClientSecret,
                    deviceCode: deviceCode,
                    interval: deviceInterval,
                  )
                  .then((tokenMap) async {
                    if (kDebugMode) {
                      debugPrint('Background device poll succeeded; token received (keys=${tokenMap.keys})');
                    }
                    try {
                      if (kDebugMode) debugPrint('Background token scopes: ${tokenMap['scope']}');
                    } catch (_) {}
                    final scopes = (tokenMap['scope'] as String?) ?? '';
                    // If we were attempting a scope upgrade and the returned token
                    // still doesn't include drive.appdata, stop auto-retries and
                    // surface an explicit UI message so the user can re-link.
                    if (_scopeUpgradeInProgress && !scopes.contains('drive.appdata')) {
                      debugPrint('Scope upgrade failed to grant drive.appdata; stopping automatic retries');
                      try {
                        await GoogleBackupService(accessToken: null).clearStoredCredentials();
                      } catch (_) {}
                      _scopeUpgradeInProgress = false;
                      _safeSetState(() {
                        _insufficientScope = true;
                        _status = 'Permisos insuficientes: concede acceso a Drive (appData) y pulsa Re-vincular.';
                        _working = false;
                      });
                      return;
                    }

                    _service = GoogleBackupService(accessToken: tokenMap['access_token'] as String?);
                    unawaited(_fetchAccountInfo(tokenMap['access_token'] as String?));
                    _safeSetState(() => _status = 'Vinculación completada');
                    // Close any open dialog and continue
                    try {
                      final navState = navigatorKey.currentState;
                      if (navState != null && navState.canPop()) navState.pop();
                    } catch (_) {}
                    await _checkForBackupAndMaybeRestore();
                  })
                  .catchError((e, s) {
                    debugPrint('Background device poll failed: $e\n$s');
                    // If polling fails, fall through to PKCE/OOB below.
                  }),
            );
          } catch (e, s) {
            if (kDebugMode) debugPrint('Failed to start background device polling: $e\n$s');
          }
        }
      } catch (e) {
        // device flow failed - fall back to PKCE loopback/OOB
      }
    }

    // choose default qrUri now (may be overridden later)
    qrUri = deviceVerificationUrl ?? verificationUriOob;
    // Debug output to help diagnose QR contents at runtime
    try {
      if (kDebugMode) debugPrint('QR URI chosen: $qrUri');
      if (kDebugMode) debugPrint('authUrl: ${authUrl.toString()}');
      if (kDebugMode) debugPrint('oobAuthUrl: ${oobAuthUrl.toString()}');
      if (kDebugMode && deviceInfo != null) debugPrint('deviceInfo: $deviceInfo');
    } catch (_) {}

    // Show the dialog regardless of whether the loopback server bound.
    // If `server` is non-null we will also await the loopback callback below.
    {
      if (kDebugMode) debugPrint('PKCE loopback bind on 127.0.0.1:$port — waiting for callback. URL: $authUrl');
      _safeSetState(() => _status = 'Esperando respuesta del navegador...');

      // Prepare a paste/QR dialog and show it while waiting for the loopback callback.
      // ensure local verification string is in sync
      verificationUriOob = oobAuthUrl.toString();
      qrUri = deviceVerificationUrl ?? verificationUriOob;
      DateTime codeExpiresAt = DateTime.now().add(const Duration(minutes: 5));
      Timer? dialogTimer;
      bool dialogVisible = true;

      void refreshAuth() {
        // regenerate PKCE verifier/challenge and authUrl, update verificationUri and expiry
        codeVerifier = base64UrlEncode(List<int>.generate(64, (i) => _randomByte()));
        bytes = sha256.convert(utf8.encode(codeVerifier)).bytes;
        codeChallenge = base64UrlEncode(bytes).replaceAll('=', '');
        authUrl = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
          queryParameters: {
            'response_type': 'code',
            'client_id': clientId,
            'redirect_uri': redirectUri,
            'scope': 'openid email profile https://www.googleapis.com/auth/drive.appdata',
            'access_type': 'offline',
            'prompt': 'consent select_account',
            'code_challenge': codeChallenge,
            'code_challenge_method': 'S256',
          },
        );
        oobAuthUrl = authUrl.replace(
          queryParameters: {...authUrl.queryParameters, 'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob'},
        );
        verificationUriOob = oobAuthUrl.toString();
        qrUri = deviceVerificationUrl ?? verificationUriOob;
        codeExpiresAt = DateTime.now().add(const Duration(minutes: 5));
      }

      late Future<bool?> dialogFuture;

      if (Platform.isAndroid || Platform.isIOS) {
        // On mobile we removed the paste/QR UI per UX request. Open the
        // browser and show a minimal dialog with actions to open or copy
        // the authorization URL so the user can complete the PKCE flow.
        try {
          final uri = Uri.tryParse(verificationUriOob);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (_) {}

        dialogFuture = showAppDialog<bool>(
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Autoriza en el navegador', style: TextStyle(color: Colors.cyanAccent)),
            content: SizedBox(
              width: min(520, MediaQuery.of(ctx).size.width * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Se ha abierto tu navegador para que inicies sesión. Si no vuelve automáticamente, usa los botones para abrir o copiar el enlace.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(verificationUriOob);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Abrir navegador'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await Clipboard.setData(ClipboardData(text: verificationUriOob));
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar enlace'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Aceptar', style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        );
      } else {
        // Desktop/other: show two-column dialog with QR + paste on left, explanation + buttons on right
        dialogFuture = showAppDialog<bool>(
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setInnerState) {
              dialogTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
                if (DateTime.now().isAfter(codeExpiresAt)) {
                  try {
                    refreshAuth();
                  } catch (_) {}
                }
                setInnerState(() {});
              });
              // remaining and userCode were used in the older QR/paste UI
              // but that UI was removed per request; keep timer ticks only.
              return AlertDialog(
                backgroundColor: Colors.black,
                content: SizedBox(
                  width: min(600, MediaQuery.of(ctx).size.width * 0.7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Inicia sesión en el navegador',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Se abrirá una ventana donde elegirás tu cuenta y concederás permisos necesarios (appData).',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(authUrl.toString());
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Abrir navegador'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                await Clipboard.setData(ClipboardData(text: authUrl.toString()));
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar enlace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Aceptar', style: TextStyle(color: Colors.cyanAccent)),
                  ),
                ],
              );
            },
          ),
        );
      }

      dialogFuture.then((_) {
        dialogTimer?.cancel();
        dialogVisible = false;
      });

      // If we bound a loopback server, wait for the browser callback and
      // exchange the code. If not, just keep the dialog visible for manual
      // flows or device-flow polling (the QR is already shown).
      if (server != null) {
        try {
          final req = await server.first.timeout(const Duration(minutes: 10));
          // If dialog still open, close it so we can show success UI
          if (dialogVisible) {
            try {
              final navState = navigatorKey.currentState;
              if (navState != null && navState.canPop()) navState.pop();
            } catch (_) {}
          }

          final params = req.uri.queryParameters;
          final code = params['code'];
          final error = params['error'];
          try {
            req.response.statusCode = 200;
            req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
            if (code != null) {
              req.response.write(
                '<html><body><h3>Autorización completada</h3><p>Puede cerrar esta ventana y volver a la aplicación.</p></body></html>',
              );
            } else {
              req.response.write(
                '<html><body><h3>Autorización fallida</h3><p>Vuelve a intentarlo en la aplicación.</p></body></html>',
              );
            }
          } catch (_) {}
          await req.response.close();
          await server.close(force: true);
          server = null;
          if (error != null) throw Exception('Authorization error: $error');
          if (code == null) throw Exception('No code returned from browser');

          final svc = GoogleBackupService(accessToken: null);
          final clientSecret = await _resolveClientSecret();
          final tokenMap = await svc.exchangeAuthCode(
            clientId: clientId,
            clientSecret: clientSecret,
            code: code,
            redirectUri: redirectUri,
            codeVerifier: codeVerifier,
          );
          _service = GoogleBackupService(accessToken: tokenMap['access_token'] as String?);
          unawaited(_fetchAccountInfo(tokenMap['access_token'] as String?));
          _safeSetState(() => _status = 'Cuenta vinculada');
          await _checkForBackupAndMaybeRestore();
          return;
        } catch (e) {
          debugPrint('Loopback PKCE failed: $e');
          if (e is TimeoutException) {
            debugPrint('PKCE loopback timed out waiting for callback (port: $port)');
            _safeSetState(() => _status = 'Tiempo de espera agotado. Usa la opción de pegar código.');
          }
          try {
            await server?.close(force: true);
          } catch (_) {}
          server = null;
        }
      }
    }

    // Paste fallback removed: single-column QR dialog eliminated per UX request.
  }

  Future<void> _checkForBackupAndMaybeRestore() async {
    if (!mounted) return;
    _safeSetState(() => _status = 'Comprobando copia de seguridad en Google Drive...');
    // Only respect the ChatProvider if it was passed in by the caller.
    // (No dynamic Provider lookups performed.)

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
      // Format size and date for display
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

      // NEVER auto-restore detected backups. Always require the user to
      // explicitly tap 'Restaurar ahora' to proceed. This enforces a manual
      // restore policy across the app.
      _safeSetState(() {
        _working = false;
      });
      return;
      // Se detectó backup; no mostramos un diálogo de confirmación automático.
      // El usuario puede pulsar 'Restaurar ahora' si desea proceder.
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
      // Google may return insufficientScopes when the granted scopes don't
      // allow access to the requested 'spaces' (for example, appDataFolder).
      // Instead of attempting an automatic PKCE scope-upgrade (which caused
      // repeated dialogs), stop and surface a clear instruction so the user
      // can re-link manually via the "Re-vincular" button. This avoids
      // reopening the QR/paste dialog unexpectedly after the user authorizes.
      if (msg.contains('The granted scopes do not give access') || msg.contains('insufficientScopes')) {
        debugPrint(
          'Detected insufficient scopes for requested spaces; verifying stored credentials before prompting re-link',
        );
        try {
          final svc = GoogleBackupService(accessToken: null);
          final creds = await svc.loadStoredCredentials();
          final storedScope = (creds?['scope'] as String?) ?? '';
          if (kDebugMode) debugPrint('Stored credential scopes: $storedScope');

          // If the stored token already claims drive.appdata, try to refresh
          // using the refresh_token before asking the user to re-link. This
          // handles cases where an access_token expired but scopes are present.
          if (storedScope.contains('drive.appdata') && creds != null && creds['refresh_token'] != null) {
            try {
              final clientId = await _resolveClientId(widget.clientId);
              final clientSecret = await _resolveClientSecret();
              final refreshed = await svc.refreshAccessToken(clientId: clientId, clientSecret: clientSecret);
              if (kDebugMode) debugPrint('Refreshed tokens after detecting appData in stored scope: ${refreshed.keys}');
              // If refresh succeeds, update service and continue flow
              _service = GoogleBackupService(accessToken: refreshed['access_token'] as String?);
              unawaited(_fetchAccountInfo(refreshed['access_token'] as String?));
              _safeSetState(() {
                _status = 'Cuenta vinculada (tokens refrescados)';
                _working = false;
              });
              await _checkForBackupAndMaybeRestore();
              return;
            } catch (e) {
              debugPrint('Refresh after stored appData scope failed: $e');
              // Fallthrough to clear and prompt re-link below
            }
          }

          // Otherwise clear stored credentials and offer the user to re-link
          // interactively now so they can explicitly grant drive.appdata.
          try {
            await svc.clearStoredCredentials();
          } catch (_) {}
          // Ask the user if they want to re-link now (this will open the
          // browser and run the PKCE/OOB flow requesting drive.appdata).
          _safeSetState(() {
            _insufficientScope = true;
            _status = 'Permisos insuficientes: concede acceso a Drive (appData).';
            _working = false;
          });
          try {
            final clientId = await _resolveClientId(widget.clientId);
            final confirm = await showAppDialog<bool>(
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.black,
                title: const Text('Permisos insuficientes', style: TextStyle(color: Colors.cyanAccent)),
                content: const Text(
                  'La cuenta vinculada no tiene permisos para acceder a appDataFolder. ¿Quieres re-vincular ahora para conceder los permisos necesarios?',
                  style: TextStyle(color: Colors.white),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Re-vincular ahora', style: TextStyle(color: Colors.cyanAccent)),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              _safeSetState(() => _working = true);
              await _pkceOobFlow(clientId);
            }
          } catch (_) {}
          return;
        } catch (_) {}
      }
      _safeSetState(() {
        _status = 'Error comprobando copia de seguridad: $e';
        _working = false;
      });
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

        // Propagate account info to caller via callback if provided.
        try {
          if (widget.onAccountInfoUpdated != null) {
            await widget.onAccountInfoUpdated!(email: _email, avatarUrl: _avatarUrl, name: _name, linked: true);
            if (kDebugMode) debugPrint('Google account propagated via onAccountInfoUpdated');
            return;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('onAccountInfoUpdated propagation failed: $e');
        }
        return;
      }

      // If unauthorized and caller allows, try to refresh using stored refresh_token
      if (resp.statusCode == 401 && attemptRefresh) {
        try {
          final clientId = await GoogleBackupService.resolveClientId(widget.clientId);
          final clientSecret = await GoogleBackupService.resolveClientSecret();
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

  Future<void> _restoreLatestNow() async {
    if (_latestBackup == null) return;
    _safeSetState(() => _status = 'Descargando copia de seguridad...');
    final svc = _service ?? GoogleBackupService(accessToken: null);
    try {
      final backupId = _latestBackup!['id'] as String;
      final file = await svc.downloadBackup(backupId);
      _safeSetState(() => _status = 'Restaurando copia de seguridad...');
      // If the caller supplied an import callback, call it with the extracted
      // JSON so the caller can apply it to its provider/state. Otherwise
      // return the JSON to the caller via Navigator.pop so onboarding can
      // import it explicitly.
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

      // No import callback: return JSON to caller for onboarding to import.
      try {
        final navState = navigatorKey.currentState;
        if (navState != null && navState.canPop()) navState.pop({'restoredJson': extractedJson});
      } catch (_) {}
      return;
    } catch (e) {
      debugPrint('restoreLatest failed: $e');
      _safeSetState(() {
        _status = 'Error restaurando copia de seguridad: $e';
        _working = false;
      });
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
          Row(
            children: [
              Row(
                children: const [
                  Icon(Icons.add_to_drive, size: 20, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Copia de seguridad en Google Drive', style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
              const Spacer(),
              // Close (X) button at top-right
              IconButton(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: 'Cerrar',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // If linked, show avatar + name above the status text
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
                ElevatedButton(
                  onPressed: _working ? null : _ensureLinkedAndCheck,
                  child: const Text('Vincular cuenta de Google'),
                ),
              ],
            ),
          ] else ...[
            // Avatar + name above the main status text (moved to top of dialog)
            const SizedBox(height: 0),
            const SizedBox(height: 8),
            Row(
              children: [
                // Left group: restore and create
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
                        // Only show 'Hacer copia ahora' when the caller provided
                        // a requestBackupJson callback.
                        if (widget.requestBackupJson != null) {
                          return ElevatedButton(
                            onPressed: _working ? null : _createBackupNow,
                            child: const Text('Hacer copia ahora'),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
                const Spacer(),
                // Right group: unlink
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
                            // Cerrar el diálogo devolviendo true para que quien lo abrió
                            // pueda refrescar su estado (p.ej. OnboardingScreen._checkGoogleLinked)
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
    if (size >= 100 || size.truncateToDouble() == size) {
      s = size.toStringAsFixed(0);
    } else if (size >= 10)
      s = size.toStringAsFixed(1);
    else
      s = size.toStringAsFixed(2);
    return '$s ${suffixes[i]}';
  }
}

// Paste UI removed — helper widget deleted.
