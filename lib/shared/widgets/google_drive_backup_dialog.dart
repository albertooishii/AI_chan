import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/app_data_utils.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:ai_chan/shared/services/google_appauth_adapter_desktop.dart';
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
  bool _insufficientScope = false;
  bool _linkInProgress = false;
  String? _lastSeenAuthUrl;
  Timer? _authUrlWatcher;

  // Helper functions for consistent backup metadata handling
  String _formatBackupTimestamp(String? isoDateString) {
    if (isoDateString == null || isoDateString.isEmpty || isoDateString == 'unknown') {
      return '';
    }

    try {
      final parsed = DateTime.tryParse(isoDateString);
      if (parsed == null) return '';

      final local = parsed.toLocal();
      final date = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
      final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      return '$date $time';
    } catch (_) {
      return '';
    }
  }

  String _formatBackupSummary(Map<String, dynamic> backup) {
    String human = '';
    try {
      final sizeStr = backup['size']?.toString();
      if (sizeStr != null) {
        final sz = int.tryParse(sizeStr) ?? 0;
        human = AppDataUtils.formatBytes(sz);
      }

      // Always use modifiedTime to show when backup was last updated
      final timestamp = _formatBackupTimestamp(backup['modifiedTime'] as String?);
      if (timestamp.isNotEmpty) {
        human = human.isNotEmpty ? '$human • $timestamp' : timestamp;
      }
    } catch (_) {}

    // Mensaje dinámico basado en si se pueden crear backups
    final prefix = _canCreateBackups()
        ? '[DATA_FOUND] Backup localizado'
        : '[ARCHIVE_DETECTED] Backup de datos disponible';

    return human.isNotEmpty ? '$prefix: $human' : prefix;
  }

  String _buildNoBackupsMessage() {
    if (!_canCreateBackups()) {
      // Solo puede ver/restaurar: mensaje informativo
      return '[CONNECTION_ESTABLISHED] Cuenta vinculada exitosamente\n\n'
          '[DRIVE_SCAN] No se detectaron archivos de backup en almacenamiento en nube\n'
          '[STANDBY_MODE] Esperando datos de backup para operaciones de sincronización';
    } else {
      // Puede crear backups: mensaje con acción
      return '[DRIVE_SCAN] No se encontraron archivos de backup en almacenamiento en nube\n'
          '[PROMPT] Inicializar primera secuencia de backup de datos';
    }
  }

  /// Determina si el usuario puede crear backups basándose en si hay datos para guardar
  bool _canCreateBackups() {
    return widget.requestBackupJson != null;
  }

  @override
  void initState() {
    super.initState();
    // Start auth URL watcher immediately so the UI detects adapter-set
    // authorization URLs even if the adapter constructs them after the
    // dialog has been shown. This makes desktop flows robust when the
    // linkAccount flow races and completes quickly.
    _startAuthUrlWatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // First, check if we already have stored credentials
      try {
        final svc = GoogleBackupService(accessToken: null);
        final token = await svc.loadStoredAccessToken();

        if (token != null) {
          // We already have credentials - just load them without auto-link
          Log.d('GoogleDriveBackupDialog: Found existing credentials, loading without auto-link', tag: 'GoogleBackup');
          await _checkStatusOnly();
          return;
        }
      } catch (e) {
        Log.d('GoogleDriveBackupDialog: Failed to check existing credentials: $e', tag: 'GoogleBackup');
      }

      // No existing credentials - proceed with auto-link
      Log.d('GoogleDriveBackupDialog: No existing credentials, starting auto-link', tag: 'GoogleBackup');
      try {
        _safeSetState(() {
          _working = true;
        });

        final candidateCid = await _resolveClientId(widget.clientId);
        // On Android explicitly force the google_sign_in path so the
        // native account chooser is shown even if cached credentials
        // exist. This ensures auto-link uses the same flow as the button.
        await GoogleBackupService(accessToken: null).linkAccount(clientId: candidateCid, forceUseGoogleSignIn: true);
        Log.d('GoogleDriveBackupDialog: Auto-link completed', tag: 'GoogleBackup');
        await _checkStatusOnly(); // Just check status, don't do additional auth
      } catch (e) {
        Log.d('GoogleDriveBackupDialog: Auto-link failed: $e', tag: 'GoogleBackup');
        // Don't show error for auto-link failures, just let user click button
        _safeSetState(() {
          _working = false;
        });
      }
    });
  }

  /// Simple status check without additional authentication attempts
  Future<void> _checkStatusOnly() async {
    Log.d('GoogleDriveBackupDialog: _checkStatusOnly start', tag: 'GoogleBackup');
    if (!mounted) return;

    try {
      final svc = GoogleBackupService(accessToken: null);
      final token = await svc.loadStoredAccessToken();

      if (token != null) {
        Log.d('GoogleDriveBackupDialog: Found stored token, checking validity', tag: 'GoogleBackup');
        _service = GoogleBackupService(accessToken: token);

        // Fetch account info and check for backups like the original method did
        try {
          Log.d('GoogleDriveBackupDialog: calling _fetchAccountInfo', tag: 'GoogleBackup');
          await _fetchAccountInfo(token, attemptRefresh: true);
          Log.d('GoogleDriveBackupDialog: _fetchAccountInfo completed successfully', tag: 'GoogleBackup');
        } catch (e) {
          Log.w('GoogleDriveBackupDialog: _fetchAccountInfo failed: $e', tag: 'GoogleBackup');
        }

        _safeSetState(() {
          _working = false;
        });
        _updateStatus('Cuenta ya vinculada');

        // Check for backups and maybe restore
        try {
          await _checkForBackupAndMaybeRestore();
        } catch (e) {
          // If we detect an unauthorized state, clear stored credentials
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
      } else {
        Log.d('GoogleDriveBackupDialog: No stored token found', tag: 'GoogleBackup');
        _safeSetState(() {
          _service = null;
          _working = false;
        });
      }
    } catch (e) {
      Log.d('GoogleDriveBackupDialog: _checkStatusOnly failed: $e', tag: 'GoogleBackup');
      _safeSetState(() {
        _service = null;
        _working = false;
      });
    }
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

    // Mensaje dinámico basado en si puede crear backups
    final checkingMessage = _canCreateBackups()
        ? '[SCAN_INITIATED] Escaneando archivos de almacenamiento en nube...'
        : '[AUTH_VERIFIED] Accediendo a interfaz de Google Drive...';
    _updateStatus(checkingMessage);

    try {
      final svc = _service ?? GoogleBackupService(accessToken: null);
      final files = await svc.listBackups();
      if (!mounted) return;

      if (files.isEmpty) {
        _latestBackup = null;
        _safeSetState(() {
          _working = false;
        });

        // Mensaje dinámico y contextual cuando no hay backups
        final emptyMessage = _buildNoBackupsMessage();
        _updateStatus(emptyMessage);
        return;
      }

      files.sort((a, b) {
        final ta = a['modifiedTime'] as String? ?? '';
        final tb = b['modifiedTime'] as String? ?? '';
        return tb.compareTo(ta);
      });
      _latestBackup = files.first;

      // Log which backup we're showing in the UI
      final backupId = _latestBackup!['id'] as String? ?? 'unknown';
      final createdTime = _latestBackup!['createdTime'] as String? ?? 'unknown';
      final modifiedTime = _latestBackup!['modifiedTime'] as String? ?? 'unknown';
      debugPrint(
        'GoogleDriveBackupDialog: Showing backup in UI - ID: $backupId, Created: $createdTime, Modified: $modifiedTime',
      );

      // Use helper function for consistent formatting
      final statusText = _formatBackupSummary(_latestBackup!);
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
              if (kDebugMode) {
                debugPrint('Refreshed tokens after detecting appData in stored scope: ${refreshed.keys}');
              }
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
          if (kDebugMode) {
            debugPrint('onAccountInfoUpdated propagation failed: $e');
          }
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
    if (!_canCreateBackups()) {
      _safeSetState(() {});
      _updateStatus('[DATA_ERROR] No hay datos serializables disponibles para operación de backup');
      return;
    }

    _safeSetState(() {});
    _updateStatus('[DATA_PREP] データコウゾウヲシリアルカチュウ...');
    File? tempBackupFile;
    try {
      final jsonStr = await widget.requestBackupJson!();
      if (jsonStr == null) throw Exception('No se pudieron obtener los datos para el backup');

      // Crear archivo temporal en la carpeta temporal del sistema
      final tempDir = await getTemporaryDirectory();
      tempBackupFile = await BackupService.createLocalBackup(
        jsonStr: jsonStr,
        destinationDirPath: tempDir.path, // Usar directorio temporal
      );

      Log.d('GoogleDriveBackupDialog: created temporary backup at ${tempBackupFile.path}', tag: 'GoogleBackup');

      _safeSetState(() {});
      _updateStatus('[UPLOAD_INITIATED] クラウドストレージニソウシンチュウ...');
      await _service!.uploadBackup(tempBackupFile);
      _safeSetState(() {});
      _updateStatus('[BACKUP_COMPLETE] データアーカイブセイジョウニアップロードカンリョウ');

      // Actualizar la información del backup (tamaño, fecha/hora) después de crear la copia
      try {
        // Wait a moment for cleanup to complete before refreshing backup info
        await Future.delayed(const Duration(milliseconds: 500));
        await _checkForBackupAndMaybeRestore();

        // Diagnose backup state after the refresh
        await _diagnoseBackupState();
      } catch (e) {
        debugPrint('Error actualizando información de backup después de crear: $e');
        // No mostrar error al usuario ya que el backup se creó correctamente
        // Solo actualizar el estado para mostrar que se completó
        _safeSetState(() => _working = false);
      }
    } catch (e) {
      debugPrint('createBackupNow error: $e');
      _safeSetState(() {});
      _updateStatus('[UPLOAD_ERROR] Archive creation/transmission failed');
    } finally {
      // Limpiar archivo temporal después del upload (exitoso o fallido)
      if (tempBackupFile != null) {
        try {
          if (await tempBackupFile.exists()) {
            await tempBackupFile.delete();
            Log.d('GoogleDriveBackupDialog: deleted temporary backup file ${tempBackupFile.path}', tag: 'GoogleBackup');
          }
        } catch (e) {
          Log.w('GoogleDriveBackupDialog: failed to delete temporary backup file: $e', tag: 'GoogleBackup');
        }
      }
    }
  }

  Future<void> _diagnoseBackupState() async {
    try {
      debugPrint('=== DIAGNÓSTICO DE BACKUP STATE ===');
      final svc = _service ?? GoogleBackupService(accessToken: null);
      final storedToken = await svc.loadStoredAccessToken();
      if (storedToken == null) {
        debugPrint('No stored access token');
        return;
      }

      final svcWithToken = GoogleBackupService(accessToken: storedToken);
      final files = await svcWithToken.listBackups();

      debugPrint('Total backups found: ${files.length}');
      for (int i = 0; i < files.length; i++) {
        final backup = files[i];
        final id = backup['id'] as String? ?? 'unknown';
        final name = backup['name'] as String? ?? 'unknown';
        final createdTime = backup['createdTime'] as String? ?? 'unknown';
        final modifiedTime = backup['modifiedTime'] as String? ?? 'unknown';
        final size = backup['size'] as String? ?? 'unknown';
        debugPrint('Backup $i: ID=$id, Name=$name, Created=$createdTime, Modified=$modifiedTime, Size=$size');

        final createdTimestamp = _formatBackupTimestamp(createdTime);
        final modifiedTimestamp = _formatBackupTimestamp(modifiedTime);

        if (createdTimestamp.isNotEmpty) {
          debugPrint('  -> Created local time: $createdTimestamp');
        }

        if (modifiedTimestamp.isNotEmpty) {
          debugPrint('  -> Modified local time: $modifiedTimestamp');
        }
      }
      debugPrint('=== FIN DIAGNÓSTICO ===');
    } catch (e) {
      debugPrint('Error in diagnose: $e');
    }
  }

  Future<void> _restoreLatestNow() async {
    if (_latestBackup == null) return;
    _safeSetState(() {});
    _updateStatus('[DOWNLOAD_INITIATED] Retrieving archive from cloud storage...');
    final svc = _service ?? GoogleBackupService(accessToken: null);
    try {
      final backupId = _latestBackup!['id'] as String;
      final file = await svc.downloadBackup(backupId);
      _safeSetState(() {});
      _updateStatus('[RESTORE_PROCESS] Decompressing and applying data...');
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
          _updateStatus('[RESTORE_ERROR] Data integration failed');
          return;
        }
      }
      try {
        final navState = navigatorKey.currentState;
        if (navState != null && navState.canPop()) {
          navState.pop({'restoredJson': extractedJson});
        }
      } catch (_) {}
      return;
    } catch (e) {
      debugPrint('restoreLatest failed: $e');
      _safeSetState(() => _working = false);
      _updateStatus('[DOWNLOAD_ERROR] Archive retrieval failed');
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
        final screenSize = MediaQuery.of(ctx).size;
        final screenW = screenSize.width;
        final screenH = screenSize.height;

        // Más generoso en desktop, más compacto en mobile
        final horizontalMargin = screenW > 800 ? 60.0 : 4.0; // Reducido aún más en mobile (4px)
        final maxWidth = screenW > 800 ? 900.0 : double.infinity; // Más grande en desktop, sin límite en mobile

        final desired = screenW - horizontalMargin;
        final width = desired.clamp(400.0, maxWidth); // Aumentado mínimo a 400px

        return Container(
          width: width,
          constraints: BoxConstraints(
            maxHeight: screenH * 0.9, // Máximo 90% de la altura de pantalla
            minHeight: 200,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0), // Más padding para que se vea más espacioso
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
                          'GOOGLE_DRIVE_INTERFACE // クラウドアーカイブカンリ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                          // Allow the title to wrap into multiple lines instead of truncating with ellipsis
                        ),
                      ),
                      IconButton(
                        // Allow closing even while a background auth flow is in progress so
                        // the user can interrupt and dismiss the dialog.
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: 'CLOSE_INTERFACE',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20), // Más espacio después del header
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
                            Text(
                              _email ?? '[AUTHENTICATED_USER]',
                              style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20), // Más espacio después de la info de usuario
                  // Show a compact summary of the latest backup when available.
                  if (_latestBackup != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        _latestBackupSummary() ?? 'ARCHIVED_DATA // クラウドストレージリヨウカノウ',
                        style: const TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                    ),
                  // Transient status message shown only when account is linked.
                  // Avoid duplicating the latest backup summary text.
                  if (_status != null && (_latestBackup == null || _status != _latestBackupSummary()))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _status!,
                        style: const TextStyle(color: Colors.white70, fontSize: 15, fontFamily: 'monospace'),
                      ),
                    ),
                ],
                // Transient status messages removed from UI per UX decision.
                const SizedBox(height: 16), // Más espacio antes de los botones

                if (!linked) ...[
                  // Platform-specific helper text
                  if (isAndroid)
                    Text(
                      '[NATIVE_AUTH] Se abrirá el selector nativo de cuentas de Android. Ejecuta "LOGIN_SEQUENCE" para seleccionar cuenta autorizada.',
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    )
                  else
                    Text(
                      '[BROWSER_REDIRECT] Se abrirá la interfaz de autenticación externa. Ejecuta "LOGIN_SEQUENCE" para iniciar el intercambio seguro. Acceso manual a URL disponible si falla el auto-lanzamiento.',
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  const SizedBox(height: 20),
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
                          label: const Text('COPY_AUTH_URL'),
                        ),
                      if (_insufficientScope)
                        Tooltip(
                          message: '[LINK_REQUIRED] Establecer conexión segura a la interfaz de almacenamiento en nube',
                          child: ElevatedButton(
                            onPressed: _linkInProgress
                                ? null
                                : () async {
                                    try {
                                      await GoogleBackupService(accessToken: null).clearStoredCredentials();
                                    } catch (_) {}
                                    setState(() => _insufficientScope = false);
                                    await _checkStatusOnly(); // Just check status, don't do additional auth
                                  },
                            child: const Text('ESTABLISH_CONNECTION'),
                          ),
                        ),
                      // The main link button: Android uses the native chooser (always visible).
                      // On desktop we only show it when an auth URL is available so the
                      // "Copiar enlace" and "Iniciar sesión" states remain consistent.
                      if (isAndroid)
                        ElevatedButton.icon(
                          onPressed: () async {
                            Log.d('GoogleDriveBackupDialog: Iniciar sesión (Android) pressed', tag: 'GoogleBackup');
                            _safeSetState(() => _working = true);
                            if (_linkInProgress) {
                              _safeSetState(() => _linkInProgress = false);
                            }
                            try {
                              // Capture last auth URL emitted by adapter before starting
                              // the interactive flow so UI can keep showing copy/sign-in.
                              try {
                                final last = GoogleAppAuthAdapter.lastAuthUrl;
                                if (last != null && last.isNotEmpty) {
                                  _safeSetState(() => _lastSeenAuthUrl = last);
                                }
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
                              await _checkStatusOnly(); // Just check status, don't do additional auth
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
                                  Log.d(
                                    'GoogleDriveBackupDialog: status=Vinculación cancelada por el usuario',
                                    tag: 'GoogleBackup',
                                  );
                                });
                              } else {
                                _safeSetState(() {
                                  _working = false;
                                  Log.d(
                                    'GoogleDriveBackupDialog: status=Error iniciando vinculaci\u00f3n',
                                    tag: 'GoogleBackup',
                                  );
                                });
                              }
                            }
                          },
                          icon: const Icon(Icons.login),
                          label: const Text('LOGIN_SEQUENCE'),
                        )
                      else if (canShowDesktopSignIn)
                        ElevatedButton.icon(
                          onPressed: () async {
                            Log.d('GoogleDriveBackupDialog: Iniciar sesión (Desktop) pressed', tag: 'GoogleBackup');
                            _safeSetState(() => _working = true);
                            if (_linkInProgress) {
                              _safeSetState(() => _linkInProgress = false);
                            }
                            try {
                              // Capture last auth URL emitted by adapter before starting
                              // the interactive flow so UI can keep showing copy/sign-in.
                              try {
                                final last = GoogleAppAuthAdapter.lastAuthUrl;
                                if (last != null && last.isNotEmpty) {
                                  _safeSetState(() => _lastSeenAuthUrl = last);
                                }
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
                              await _checkStatusOnly(); // Just check status, don't do additional auth
                            } catch (e, st) {
                              Log.d('GoogleDriveBackupDialog: Desktop linkAccount threw: $e', tag: 'GoogleBackup');
                              debugPrint('Desktop sign-in error: $e\n$st');
                              _safeSetState(() {
                                _working = false;
                                Log.d(
                                  'GoogleDriveBackupDialog: status=Error iniciando vinculación',
                                  tag: 'GoogleBackup',
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.login),
                          label: const Text('LOGIN_SEQUENCE'),
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
                      final unlinkButton = OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () async {
                                final confirm = await showAppDialog<bool>(
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: Colors.black,
                                    title: const Text(
                                      'DISCONNECT_INTERFACE',
                                      style: TextStyle(color: Colors.cyanAccent),
                                    ),
                                    content: const Text(
                                      '[SECURITY_PROTOCOL] Confirma la desconexión de la interfaz de almacenamiento en nube. Los tokens de autenticación locales serán eliminados.',
                                      style: TextStyle(fontFamily: 'monospace'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(true),
                                        child: const Text('DISCONNECT', style: TextStyle(color: Colors.redAccent)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  setState(() {
                                    _working = true;
                                  });
                                  _updateStatus('[DISCONNECT_INIT] Terminating account interface...');
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
                                  _updateStatus('[DISCONNECT_SUCCESS] Account interface terminated successfully');
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
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48), // Mismo tamaño que otros botones
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        icon: const Icon(Icons.link_off, color: Colors.redAccent),
                        label: const Text('DISCONNECT', style: TextStyle(color: Colors.redAccent)),
                      );

                      final hasRestore = _latestBackup != null;
                      final hasCreate = _canCreateBackups();

                      // Build the primary action buttons once and reuse them in the
                      // wide/narrow layouts to avoid duplicating widget code.
                      final restoreButton = ElevatedButton.icon(
                        icon: const Icon(Icons.restore),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48), // Botones más altos
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: _working ? null : _restoreLatestNow,
                        label: const Text('RESTORE_DATA'),
                      );

                      final createButton = ElevatedButton.icon(
                        icon: const Icon(Icons.backup),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48), // Botones más altos
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: _working ? null : _createBackupNow,
                        label: const Text('UPLOAD_DATA'),
                      );

                      final deleteButton = OutlinedButton.icon(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48), // Botones más altos
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        onPressed: (_working || _latestBackup == null)
                            ? null
                            : () async {
                                final confirm = await showAppDialog<bool>(
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: Colors.black,
                                    title: const Text('DELETE_ARCHIVE', style: TextStyle(color: Colors.redAccent)),
                                    content: const Text(
                                      '[WARNING] Permanent deletion of cloud storage archive is irreversible.\n\n'
                                      '[CONFIRM] ¿Estás seguro? Esto eliminará el archivo remoto sin posibilidad de recuperación.\n\n'
                                      '[ABORT] Si no estás seguro, selecciona CANCEL. [EXECUTE] Para liberar espacio o eliminar datos sensibles, confirma la eliminación.',
                                      style: TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(true),
                                        child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                // Proceed with deletion
                                _safeSetState(() => _working = true);
                                _updateStatus('[DELETE_INITIATED] Purging backup archive...');
                                try {
                                  final svc = _service ?? GoogleBackupService(accessToken: null);
                                  final id = _latestBackup!['id'] as String;
                                  await svc.deleteBackup(id);
                                  // Refresh list
                                  _latestBackup = null;
                                  _updateStatus('[DELETE_COMPLETE] Backup archive purged from cloud storage');
                                } catch (e) {
                                  debugPrint('deleteBackup failed: $e');
                                  _updateStatus('[DELETE_ERROR] Failed to purge backup archive');
                                } finally {
                                  _safeSetState(() => _working = false);
                                }
                              },
                        label: const Text('DELETE_ARCHIVE', style: TextStyle(color: Colors.redAccent)),
                      );

                      // Layout inteligente y responsivo de botones
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth = constraints.maxWidth;

                          // Crear lista de botones principales (sin desvincular)
                          final primaryButtons = <Widget>[];
                          if (hasRestore) primaryButtons.add(restoreButton);
                          if (hasCreate) primaryButtons.add(createButton);
                          if (_latestBackup != null) {
                            primaryButtons.add(deleteButton);
                          }

                          // Layout muy estrecho: todos los botones apilados verticalmente
                          if (availableWidth < 350) {
                            final List<Widget> allButtons = [];
                            for (int i = 0; i < primaryButtons.length; i++) {
                              if (i > 0) {
                                allButtons.add(const SizedBox(height: 12));
                              }
                              allButtons.add(SizedBox(width: double.infinity, child: primaryButtons[i]));
                            }
                            // Desvincular al final
                            if (primaryButtons.isNotEmpty) {
                              allButtons.add(const SizedBox(height: 12));
                            }
                            allButtons.add(SizedBox(width: double.infinity, child: unlinkButton));

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: allButtons,
                            );
                          }

                          // Layout mediano: botones principales en Wrap, desvincular abajo si no cabe
                          if (availableWidth < 600) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (primaryButtons.isNotEmpty)
                                  Wrap(spacing: 8.0, runSpacing: 8.0, children: primaryButtons),
                                if (primaryButtons.isNotEmpty) const SizedBox(height: 12),
                                SizedBox(width: double.infinity, child: unlinkButton),
                              ],
                            );
                          }

                          // Layout ancho (desktop): botones principales a la izquierda, desvincular a la derecha pero abajo
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.end, // Alinear hacia abajo
                            children: [
                              Expanded(
                                child: primaryButtons.isEmpty
                                    ? const SizedBox()
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(spacing: 12.0, runSpacing: 8.0, children: primaryButtons),
                                      ),
                              ),
                              if (primaryButtons.isNotEmpty) const SizedBox(width: 16),
                              unlinkButton,
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12), // Espacio final más generoso
              ],
            ),
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

  String? _latestBackupSummary() {
    if (_latestBackup == null) return null;
    try {
      return _formatBackupSummary(_latestBackup!);
    } catch (_) {
      return null;
    }
  }
}
