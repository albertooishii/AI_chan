import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
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
  String? _status;
  GoogleBackupService? _service;
  Map<String, dynamic>? _latestBackup;
  String? _email;
  String? _avatarUrl;
  String? _name;
  bool _working = false;
  bool _hasChatProvider = false;
  bool _insufficientScope = false;
  bool _linkInProgress = false;
  bool _userCancelledSignIn = false;
  // removed _usingNativeAppAuth (no longer needed)

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
    if (_linkInProgress) return;
    _safeSetState(() {
      _linkInProgress = true;
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

      // If the user previously cancelled the native chooser, don't reopen it automatically.
      if (_userCancelledSignIn) {
        _safeSetState(() {
          _status = 'No vinculada';
          _working = false;
        });
        return;
      }

      _safeSetState(() {
        _status = 'Iniciando vinculación...';
        _working = true;
      });

      try {
        final tokenMap = await GoogleBackupService(accessToken: null).linkAccount(clientId: candidateCid);
        if (tokenMap['access_token'] != null) {
          _service = GoogleBackupService(accessToken: tokenMap['access_token'] as String?);
          unawaited(_fetchAccountInfo(tokenMap['access_token'] as String?));
          _safeSetState(() => _status = 'Vinculación completada');
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
        } catch (_) {}
        _safeSetState(() {
          _status = statusMsg;
          _working = false;
        });
      }
    } catch (e) {
      debugPrint('ensureLinkedAndCheck error: $e');
      _safeSetState(() {
        _status = 'Error al vincular';
        _working = false;
      });
    } finally {
      _safeSetState(() {
        _linkInProgress = false;
      });
    }
  }

  // PKCE/AppAuth flow moved to GoogleBackupService.linkAccount(); dialog is UI-only now.

  // Authorization wait dialog removed: flow is automatic and waits silently for loopback capture

  // URL launcher helper removed; dialog delegates auth to service and no longer opens URLs.

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
      _safeSetState(() => _status = 'Error creando/subiendo copia de seguridad');
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
            _status = 'Error importando copia de seguridad';
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
      _safeSetState(() => _status = 'Error restaurando copia de seguridad');
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
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_insufficientScope)
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
                // The main link button is hidden in this UI variant; keep it in code
                // for quick re-enable but not shown to users.
                ElevatedButton(
                  onPressed: _working
                      ? null
                      : () async {
                          // Clear the previous cancellation marker and start sign-in manually
                          _userCancelledSignIn = false;
                          await _ensureLinkedAndCheck();
                        },
                  child: const Text('Iniciar sesión'),
                ),
                // local serverAuthCode exchange UI removed per request.
                // Manual PKCE buttons removed; dialog delegates auth to service.
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
    } else if (size >= 10) {
      s = size.toStringAsFixed(1);
    } else {
      s = size.toStringAsFixed(2);
    }
    return '$s ${suffixes[i]}';
  }
}

// Note: inline HTML fallbacks removed. The flow now requires packaged
// assets `assets/oauth_start.html` and `assets/oauth_success.html`. If those
// assets are missing the loopback flow will abort and the manual paste dialog
// will be used instead.
