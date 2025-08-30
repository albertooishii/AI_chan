import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:ai_chan/shared/services/google_appauth_adapter_desktop.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/main.dart' show navigatorKey;
import 'package:ai_chan/shared/utils/dialog_utils.dart';

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
  // _status holds a transient message that is shown in the dialog only when
  // the account is already linked. All other status events are logged.
  GoogleBackupService? _service;
  String? _status;
  Map<String, dynamic>? _latestBackup;
  String? _email;
  String? _avatarUrl;
  String? _name;
  bool _working = false;
  bool _hasChatProvider = false;
  bool _insufficientScope = false;
  bool _linkInProgress = false;
  bool _userCancelledSignIn = false;
  DateTime? _lastAuthFailureAt;
  String? _lastSeenAuthUrl;
  Timer? _authUrlWatcher;
  // removed _usingNativeAppAuth (no longer needed)

  @override
  void initState() {
    super.initState();
    // Start auth URL watcher immediately so the UI detects adapter-set
    // authorization URLs even if the adapter constructs them after the
    // dialog has been shown. This makes desktop flows robust when the
    // linkAccount flow races and completes quickly.
    _startAuthUrlWatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureLinkedAndCheck();
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _updateStatus(String msg) {
    // Always log for diagnostics
    Log.d('GoogleDriveBackupDialog: status=$msg', tag: 'GoogleBackup');
    // Only update visible dialog state when the account is linked.
    // Store the message for visible UI only when linked; clear otherwise.
    _safeSetState(() {
      _status = (_service != null) ? msg : null;
    });
  }

  Future<String> _resolveClientId(String rawCid) async => await GoogleBackupService.resolveClientId(rawCid);
  Future<String?> _resolveClientSecret() async => await GoogleBackupService.resolveClientSecret();

  Future<void> _ensureLinkedAndCheck() async {
    Log.d('GoogleDriveBackupDialog: _ensureLinkedAndCheck start', tag: 'GoogleBackup');
    if (!mounted) return;
    if (_linkInProgress) return;
    _safeSetState(() {
      _linkInProgress = true;
      // Do not set a transient 'Iniciando vinculación...' status here; keep status updates
      // minimal to avoid flicker. The UI will update with persistent states like
      // 'Cuenta ya vinculada' or error messages.
      _working = true;
    });

    try {
      _hasChatProvider = (widget.requestBackupJson != null || widget.onImportedJson != null);

      final candidateCid = await _resolveClientId(widget.clientId);
      final svc = GoogleBackupService(accessToken: null);
      final token = await svc.loadStoredAccessToken();

      if (token != null) {
        // Reuse stored credentials instead of clearing them on dialog open.
        // Clearing should only happen on explicit user action or when we
        // detect invalid scopes/expired tokens during an operation.
        _service = GoogleBackupService(accessToken: token);
        try {
          await _fetchAccountInfo(token, attemptRefresh: true);
        } catch (_) {}
        _safeSetState(() {});
        _updateStatus('Cuenta ya vinculada');
        try {
          await _checkForBackupAndMaybeRestore();
        } catch (e) {
          // If we detect an unauthorized state while checking backups, clear stored credentials
          if (e is StateError && e.message == 'Unauthorized') {
            try {
              await GoogleBackupService(accessToken: null).clearStoredCredentials();
            } catch (_) {}
            _safeSetState(() {
              _service = null;
              _working = false;
            });
            _updateStatus('No vinculada');
            return;
          }
          rethrow;
        }
        return;
      }

      // If the user previously cancelled the native chooser, don't reopen it automatically.
      if (_userCancelledSignIn) {
        _safeSetState(() {
          _working = false;
        });
        _updateStatus('No vinculada');
        return;
      }

      // If we recently failed an AppAuth attempt, avoid automatically restarting
      // another one immediately when the dialog is reopened. This prevents
      // repeated loopback bindings and timeouts. Allow manual retry via the
      // 'Iniciar sesión' button.
      if (_lastAuthFailureAt != null) {
        final diff = DateTime.now().difference(_lastAuthFailureAt!);
        if (diff.inSeconds < 30) {
          _safeSetState(() {
            _working = false;
          });
          _updateStatus('Intento previo de autenticación falló recientemente. Pulsa "Iniciar sesión" para reintentar.');
          return;
        }
      }

      // Intentionally do not set a generic 'Iniciando vinculación...' status; the click
      // handler now sets a clearer 'Iniciando vinculación manual...' when appropriate.

      try {
        // Start watching the adapter's static `lastAuthUrl` while an
        // automatic linking flow is running. This covers the case where
        // linkAccount constructs the authorization URL after the dialog
        // started and the UI would otherwise not show the copy/sign-in
        // buttons.
        _startAuthUrlWatcher();

        // If we're on desktop and an auth URL is already available (for
        // example because a previous link attempt constructed it), try to
        // open the browser proactively. This handles the case where the
        // dialog was closed while a linkAccount flow was in-flight and the
        // system browser was opened earlier — reopening the dialog should
        // also try to bring up the browser so the user continues the flow.
        try {
          final isDesktop = !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
          final hasAuthUrlLocal =
              ((GoogleAppAuthAdapter.lastAuthUrl != null && GoogleAppAuthAdapter.lastAuthUrl!.isNotEmpty) ||
              (_lastSeenAuthUrl != null && _lastSeenAuthUrl!.isNotEmpty));
          if (isDesktop && hasAuthUrlLocal) {
            final copyUrl = (GoogleAppAuthAdapter.lastAuthUrl != null && GoogleAppAuthAdapter.lastAuthUrl!.isNotEmpty)
                ? GoogleAppAuthAdapter.lastAuthUrl!
                : (_lastSeenAuthUrl ?? '');
            if (copyUrl.isNotEmpty) {
              try {
                Log.d('GoogleDriveBackupDialog: trying to re-open browser for desktop auth', tag: 'GoogleBackup');
                await GoogleAppAuthAdapter.openBrowser(copyUrl);
                Log.d('GoogleDriveBackupDialog: re-opened browser for desktop auth', tag: 'GoogleBackup');
              } catch (e) {
                Log.w('GoogleDriveBackupDialog: re-open browser failed: $e', tag: 'GoogleBackup');
              }
            }
          }
        } catch (_) {}

        final isAndroid = !kIsWeb && Platform.isAndroid;
        // On Android we want the native account chooser to open automatically
        // whenever the dialog starts an automatic linking flow.
        final tokenMap = await GoogleBackupService(
          accessToken: null,
        ).linkAccount(clientId: candidateCid, forceUseGoogleSignIn: isAndroid);
        if (tokenMap['access_token'] != null) {
          _service = GoogleBackupService(accessToken: tokenMap['access_token'] as String?);
          unawaited(_fetchAccountInfo(tokenMap['access_token'] as String?));
          _safeSetState(() {});
          _updateStatus('Vinculación completada');
          await _checkForBackupAndMaybeRestore();
          return;
        }
      } catch (e) {
        debugPrint('ensureLinkedAndCheck: linkAccount failed: $e');
        String statusMsg = 'Fallo al vincular';
        try {
          final raw = (e is StateError) ? e.message.toString() : e.toString();
          final m = raw.toLowerCase();
          // Broadly detect cancellation-like messages from various plugin versions
          if (m.contains('cancel') ||
              m.contains('user cancelled') ||
              m.contains('user canceled') ||
              m.contains('user_cancel')) {
            statusMsg = 'Vinculación cancelada por el usuario';
            _userCancelledSignIn = true;
          }
          // Detect AppAuth timeouts/failures and record timestamp to avoid
          // immediately retrying when the dialog is reopened.
          if (m.contains('appauth') || m.contains('timeout') || m.contains('fallo en la autenticación')) {
            _lastAuthFailureAt = DateTime.now();
          }
        } catch (_) {}
        _safeSetState(() {
          _working = false;
        });
        _updateStatus(statusMsg);
      }
    } catch (e) {
      debugPrint('ensureLinkedAndCheck error: $e');
      _safeSetState(() {
        _working = false;
      });
      _updateStatus('Error al vincular');
    } finally {
      _stopAuthUrlWatcher();
      _safeSetState(() {
        _linkInProgress = false;
      });
    }
  }

  void _startAuthUrlWatcher() {
    try {
      _authUrlWatcher?.cancel();
      _authUrlWatcher = Timer.periodic(const Duration(milliseconds: 300), (_) {
        try {
          final last = GoogleAppAuthAdapter.lastAuthUrl;
          if (last != null && last.isNotEmpty && last != _lastSeenAuthUrl) {
            _safeSetState(() => _lastSeenAuthUrl = last);
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _stopAuthUrlWatcher() {
    try {
      _authUrlWatcher?.cancel();
      _authUrlWatcher = null;
    } catch (_) {}
  }

  // PKCE/AppAuth flow moved to GoogleBackupService.linkAccount(); dialog is UI-only now.

  // Authorization wait dialog removed: flow is automatic and waits silently for loopback capture

  // URL launcher helper removed; dialog delegates auth to service and no longer opens URLs.

  // _extractCodeFromUrlOrCode removed (manual paste flow disabled)

  // Manual paste dialog removed by request.

  Future<void> _checkForBackupAndMaybeRestore() async {
    if (!mounted) return;
    _safeSetState(() {});
    _updateStatus('Comprobando copia de seguridad en Google Drive...');
    try {
      final svc = _service ?? GoogleBackupService(accessToken: null);
      final files = await svc.listBackups();
      if (!mounted) return;
      if (files.isEmpty) {
        _latestBackup = null;
        if (!_hasChatProvider) {
          _safeSetState(() {
            _working = false;
          });
          _updateStatus('Cuenta vinculada correctamente.');
          return;
        }
        _safeSetState(() {
          _working = false;
        });
        _updateStatus('No hay copias de seguridad en Google Drive');
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
      _safeSetState(() => _working = false);
      _updateStatus(statusText);
      return;
    } catch (e) {
      final msg = e.toString();
      debugPrint('checkForBackup error: $msg');
      // Detect unauthorized responses from Drive/API and clear stored creds.
      if (msg.contains('Invalid Credentials') || msg.contains('Expected OAuth 2 access token')) {
        try {
          await GoogleBackupService(accessToken: null).clearStoredCredentials();
        } catch (_) {}
        // Bubble up a StateError so callers (ensureLinkedAndCheck) can react.
        throw StateError('Unauthorized');
      }
      if (msg.contains('invalid_scope')) {
        try {
          await GoogleBackupService(accessToken: null).clearStoredCredentials();
        } catch (_) {}
        _insufficientScope = true;
        _safeSetState(() {
          _working = false;
        });
        _updateStatus('Permisos insuficientes al acceder a Drive. Se han borrado las credenciales locales.');
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
        // If we reach here, refresh failed or was not possible. Treat as unauthorized.
        throw StateError('Unauthorized');
      }
      if (resp.statusCode == 401 && !attemptRefresh) {
        // No refresh attempted and got 401 - treat as unauthorized.
        throw StateError('Unauthorized');
      }
      debugPrint('userinfo request failed: ${resp.statusCode} ${resp.body}');
    } catch (e) {
      debugPrint('userinfo request error: $e');
      rethrow;
    }
  }

  Future<void> _createBackupNow() async {
    if (_service == null) return;
    if (widget.requestBackupJson == null) {
      _safeSetState(() {});
      _updateStatus('Para crear una copia en Google Drive, proporciona un callback requestBackupJson.');
      return;
    }

    _safeSetState(() {});
    _updateStatus('Creando copia de seguridad local...');
    try {
      final jsonStr = await widget.requestBackupJson!();
      if (jsonStr == null) throw Exception('requestBackupJson devolvió null');
      final file = await BackupService.createLocalBackup(jsonStr: jsonStr);
      _safeSetState(() {});
      _updateStatus('Subiendo copia de seguridad a Google Drive...');
      await _service!.uploadBackup(file);
      _safeSetState(() {});
      _updateStatus('Copia subida correctamente');
    } catch (e) {
      debugPrint('createBackupNow error: $e');
      _safeSetState(() {});
      _updateStatus('Error creando/subiendo copia de seguridad');
    }
  }

  Future<void> _restoreLatestNow() async {
    if (_latestBackup == null) return;
    _safeSetState(() {});
    _updateStatus('Descargando copia de seguridad...');
    final svc = _service ?? GoogleBackupService(accessToken: null);
    try {
      final backupId = _latestBackup!['id'] as String;
      final file = await svc.downloadBackup(backupId);
      _safeSetState(() {});
      _updateStatus('Restaurando copia de seguridad...');
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
            _working = false;
          });
          _updateStatus('Error importando copia de seguridad');
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
      _safeSetState(() => _working = false);
      _updateStatus('Error restaurando copia de seguridad');
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _service != null;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isDesktop = !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
    final hasAuthUrl =
        ((GoogleAppAuthAdapter.lastAuthUrl != null && GoogleAppAuthAdapter.lastAuthUrl!.isNotEmpty) ||
        (_lastSeenAuthUrl != null && _lastSeenAuthUrl!.isNotEmpty));
    // Only show the desktop sign-in button when we actually have an authorization
    // URL available. This keeps the "Copiar enlace" and "Iniciar sesión" buttons
    // consistent: both depend on an auth URL being present.
    final canShowDesktopSignIn = isDesktop && hasAuthUrl;
    Log.d(
      'GoogleDriveBackupDialog: build linked=$linked working=$_working lastAuthUrl=${GoogleAppAuthAdapter.lastAuthUrl ?? '<null>'}',
      tag: 'GoogleBackup',
    );
    // Make the dialog adapt to smaller screens: compute a sensible width
    // based on the current screen width and a small horizontal margin so
    // the dialog doesn't appear excessively narrow on mobile devices.
    return Builder(
      builder: (ctx) {
        final screenW = MediaQuery.of(ctx).size.width;
        final desired = screenW - 24; // 12px margin each side
        final width = desired.clamp(320.0, 560.0);
        return SizedBox(
          width: width,
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
                    Expanded(
                      child: Text(
                        'Copia de seguridad en Google Drive',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        // Allow the title to wrap into multiple lines instead of truncating with ellipsis
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
                // Show a compact summary of the latest backup when available.
                if (_latestBackup != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      _latestBackupSummary() ?? 'Copia de seguridad disponible',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                // Transient status message shown only when account is linked.
                // Avoid duplicating the latest backup summary text.
                if (_status != null && (_latestBackup == null || _status != _latestBackupSummary()))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(_status!, style: const TextStyle(color: Colors.white70)),
                  ),
              ],
              // Transient status messages removed from UI per UX decision.
              const SizedBox(height: 12),

              if (!linked) ...[
                // Platform-specific helper text
                if (isAndroid)
                  Text(
                    'Se abrirá el selector nativo de cuentas en Android. Pulsa "Iniciar sesión" para elegir la cuenta.',
                    style: const TextStyle(color: Colors.white70),
                  )
                else
                  Text(
                    'Se abrirá tu navegador para elegir la cuenta. Pulsa "Iniciar sesión" para iniciar el proceso. Si no se abre automáticamente, puedes copiar la URL y abrirla manualmente una vez esté disponible.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Desktop: show copy only when we have a prepared auth URL
                    if (isDesktop && hasAuthUrl)
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final copyUrl =
                                (GoogleAppAuthAdapter.lastAuthUrl != null &&
                                    GoogleAppAuthAdapter.lastAuthUrl!.isNotEmpty)
                                ? GoogleAppAuthAdapter.lastAuthUrl!
                                : (_lastSeenAuthUrl ?? '');
                            await Clipboard.setData(ClipboardData(text: copyUrl));
                            showAppSnackBar('Enlace copiado al portapapeles');
                          } catch (e) {
                            debugPrint('copy url failed: $e');
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar enlace'),
                      ),
                    if (_insufficientScope)
                      Tooltip(
                        message: 'Pulsa para volver a vincular y conceder acceso a Google Drive',
                        child: ElevatedButton(
                          onPressed: _linkInProgress
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
                    // The main link button: Android uses the native chooser (always visible).
                    // On desktop we only show it when an auth URL is available so the
                    // "Copiar enlace" and "Iniciar sesión" states remain consistent.
                    if (isAndroid)
                      ElevatedButton.icon(
                        onPressed: () async {
                          Log.d('GoogleDriveBackupDialog: Iniciar sesión (Android) pressed', tag: 'GoogleBackup');
                          _userCancelledSignIn = false;
                          _safeSetState(() => _working = true);
                          if (_linkInProgress) _safeSetState(() => _linkInProgress = false);
                          try {
                            // Capture last auth URL emitted by adapter before starting
                            // the interactive flow so UI can keep showing copy/sign-in.
                            try {
                              final last = GoogleAppAuthAdapter.lastAuthUrl;
                              if (last != null && last.isNotEmpty) _safeSetState(() => _lastSeenAuthUrl = last);
                            } catch (_) {}
                            final candidateCid = await _resolveClientId(widget.clientId);
                            // On Android explicitly force the google_sign_in path so the
                            // native account chooser is shown even if cached credentials
                            // exist. This ensures the button always opens the native
                            // selector as the UX expects.
                            await GoogleBackupService(
                              accessToken: null,
                            ).linkAccount(clientId: candidateCid, forceUseGoogleSignIn: true);
                            Log.d('GoogleDriveBackupDialog: Android linkAccount returned', tag: 'GoogleBackup');
                            await _ensureLinkedAndCheck();
                          } catch (e, st) {
                            // Log and treat user cancellations specially so the UI
                            // does not present an error for an intentional cancel.
                            Log.d('GoogleDriveBackupDialog: Android linkAccount threw: $e', tag: 'GoogleBackup');
                            debugPrint('Android sign-in error: $e\n$st');
                            final raw = e.toString().toLowerCase();
                            if (raw.contains('user cancelled') ||
                                raw.contains('user canceled') ||
                                raw.contains('cancel')) {
                              _safeSetState(() {
                                _working = false;
                                _userCancelledSignIn = true;
                                Log.d(
                                  'GoogleDriveBackupDialog: status=Vinculación cancelada por el usuario',
                                  tag: 'GoogleBackup',
                                );
                              });
                            } else {
                              _safeSetState(() {
                                _working = false;
                                _lastAuthFailureAt = DateTime.now();
                                Log.d(
                                  'GoogleDriveBackupDialog: status=Error iniciando vinculaci\u00f3n',
                                  tag: 'GoogleBackup',
                                );
                              });
                            }
                          }
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión'),
                      )
                    else if (canShowDesktopSignIn)
                      ElevatedButton.icon(
                        onPressed: () async {
                          Log.d('GoogleDriveBackupDialog: Iniciar sesión (Desktop) pressed', tag: 'GoogleBackup');
                          _userCancelledSignIn = false;
                          _safeSetState(() => _working = true);
                          if (_linkInProgress) _safeSetState(() => _linkInProgress = false);
                          try {
                            // Capture last auth URL emitted by adapter before starting
                            // the interactive flow so UI can keep showing copy/sign-in.
                            try {
                              final last = GoogleAppAuthAdapter.lastAuthUrl;
                              if (last != null && last.isNotEmpty) _safeSetState(() => _lastSeenAuthUrl = last);
                            } catch (_) {}
                            // If we already have an auth URL available, try to open it
                            // explicitly as a fallback so the user sees the browser.
                            try {
                              final copyUrl =
                                  (GoogleAppAuthAdapter.lastAuthUrl != null &&
                                      GoogleAppAuthAdapter.lastAuthUrl!.isNotEmpty)
                                  ? GoogleAppAuthAdapter.lastAuthUrl!
                                  : (_lastSeenAuthUrl ?? '');
                              if (copyUrl.isNotEmpty) {
                                Log.d(
                                  'GoogleDriveBackupDialog: attempting to open browser for desktop auth',
                                  tag: 'GoogleBackup',
                                );
                                try {
                                  await GoogleAppAuthAdapter.openBrowser(copyUrl);
                                  Log.d(
                                    'GoogleDriveBackupDialog: openBrowser invoked for desktop auth',
                                    tag: 'GoogleBackup',
                                  );
                                } catch (e) {
                                  Log.w(
                                    'GoogleDriveBackupDialog: openBrowser fallback failed: $e',
                                    tag: 'GoogleBackup',
                                  );
                                  showAppSnackBar(
                                    'No se pudo abrir el navegador automáticamente. Puedes copiar el enlace.',
                                  );
                                }
                              }
                            } catch (_) {}

                            final candidateCid = await _resolveClientId(widget.clientId);
                            await GoogleBackupService(accessToken: null).linkAccount(clientId: candidateCid);
                            Log.d('GoogleDriveBackupDialog: Desktop linkAccount returned', tag: 'GoogleBackup');
                            await _ensureLinkedAndCheck();
                          } catch (e, st) {
                            Log.d('GoogleDriveBackupDialog: Desktop linkAccount threw: $e', tag: 'GoogleBackup');
                            debugPrint('Desktop sign-in error: $e\n$st');
                            _safeSetState(() {
                              _working = false;
                              Log.d('GoogleDriveBackupDialog: status=Error iniciando vinculación', tag: 'GoogleBackup');
                            });
                          }
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión'),
                      ),
                    // local serverAuthCode exchange UI removed per request.
                    // Manual PKCE buttons removed; dialog delegates auth to service.
                  ],
                ),
              ] else ...[
                const SizedBox(height: 0),
                const SizedBox(height: 8),
                // Use a Wrap so buttons try to stay in one line and wrap to the
                // next line automatically when they don't fit.
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final narrow = constraints.maxWidth < 420;
                    final unlinkButton = OutlinedButton.icon(
                      onPressed: _working
                          ? null
                          : () async {
                              final confirm = await showAppDialog<bool>(
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Colors.black,
                                  title: const Text('Desvincular cuenta', style: TextStyle(color: Colors.cyanAccent)),
                                  content: const Text(
                                    '¿Seguro que quieres desvincular la cuenta de Google? Se borrarán las credenciales locales.',
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
                                });
                                _updateStatus('Desvinculando cuenta...');
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
                                });
                                _updateStatus('Cuenta desvinculada');
                                try {
                                  if (widget.onClearAccountInfo != null) {
                                    widget.onClearAccountInfo!();
                                  }
                                } catch (_) {}
                                try {
                                  final navState = navigatorKey.currentState;
                                  if (navState != null && navState.canPop()) {
                                    navState.pop(true);
                                  }
                                } catch (_) {}
                              }
                            },
                      icon: const Icon(Icons.link_off, color: Colors.redAccent),
                      label: const Text('Desvincular', style: TextStyle(color: Colors.redAccent)),
                    );

                    final hasRestore = _latestBackup != null;
                    final hasCreate = widget.requestBackupJson != null;

                    // Build the primary action buttons once and reuse them in the
                    // wide/narrow layouts to avoid duplicating widget code.
                    final restoreButton = ElevatedButton.icon(
                      icon: const Icon(Icons.restore),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _working ? null : _restoreLatestNow,
                      label: const Text('Restaurar copia de seguridad'),
                    );

                    final createButton = ElevatedButton.icon(
                      icon: const Icon(Icons.backup),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _working ? null : _createBackupNow,
                      label: const Text('Guardar copia actual'),
                    );

                    final deleteButton = OutlinedButton.icon(
                      icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: (_working || _latestBackup == null)
                          ? null
                          : () async {
                              final confirm = await showAppDialog<bool>(
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Colors.black,
                                  title: const Text(
                                    'Eliminar copia de seguridad',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                  content: const Text(
                                    'Eliminar la copia de seguridad permanente de Google Drive es irreversible.\n\n'
                                    '¿Estás seguro? Esto eliminará el archivo remoto y no podrá recuperarse.\n\n'
                                    'Si no estás seguro, pulsa cancelar. Si quieres liberar espacio o retirar datos sensibles, confirma.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                              // Proceed with deletion
                              _safeSetState(() => _working = true);
                              _updateStatus('Eliminando copia de seguridad...');
                              try {
                                final svc = _service ?? GoogleBackupService(accessToken: null);
                                final id = _latestBackup!['id'] as String;
                                await svc.deleteBackup(id);
                                // Refresh list
                                _latestBackup = null;
                                _updateStatus('Copia de seguridad eliminada correctamente');
                              } catch (e) {
                                debugPrint('deleteBackup failed: $e');
                                _updateStatus('Error al eliminar la copia de seguridad');
                              } finally {
                                _safeSetState(() => _working = false);
                              }
                            },
                      label: const Text('Eliminar copia de seguridad', style: TextStyle(color: Colors.redAccent)),
                    );

                    // Wide layout: primary actions left, unlink button on the right
                    if (!narrow) {
                      final primary = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasRestore) restoreButton,
                          if (hasRestore && (hasCreate || _latestBackup != null)) const SizedBox(width: 8),
                          if (hasCreate) createButton,
                          if (hasCreate && _latestBackup != null) const SizedBox(width: 8),
                          if (_latestBackup != null) deleteButton,
                        ],
                      );

                      return Row(
                        children: [
                          Expanded(
                            child: Align(alignment: Alignment.centerLeft, child: primary),
                          ),
                          const SizedBox(width: 12),
                          unlinkButton,
                        ],
                      );
                    }

                    // Narrow layout: stack every button vertically (one per line)
                    // to ensure no horizontal wrapping and avoid duplicated code.
                    final List<Widget> stacked = [];
                    if (hasRestore) stacked.add(SizedBox(width: double.infinity, child: restoreButton));
                    if (hasCreate) {
                      if (stacked.isNotEmpty) stacked.add(const SizedBox(height: 8));
                      stacked.add(SizedBox(width: double.infinity, child: createButton));
                    }
                    // Add spacing then unlink as a full-width button as well so
                    // all actions appear one-per-line on narrow screens.
                    if (stacked.isNotEmpty) stacked.add(const SizedBox(height: 8));
                    // Add delete button between create and unlink in stacked narrow layout
                    if (hasCreate && _latestBackup != null) {
                      stacked.add(SizedBox(width: double.infinity, child: deleteButton));
                      stacked.add(const SizedBox(height: 8));
                    }
                    stacked.add(SizedBox(width: double.infinity, child: unlinkButton));

                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: stacked);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _stopAuthUrlWatcher();
    super.dispose();
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
    } else if (size >= 10) {
      s = size.toStringAsFixed(1);
    } else {
      s = size.toStringAsFixed(2);
    }
    return '$s ${suffixes[i]}';
  }

  String? _latestBackupSummary() {
    if (_latestBackup == null) return null;
    try {
      String human = '';
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
      return human.isNotEmpty ? 'Copia de seguridad disponible: $human' : 'Copia de seguridad disponible';
    } catch (_) {
      return null;
    }
  }
}
