import 'package:flutter/material.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Widget helper para testing y manejo fácil de la vinculación con Google Drive
class GoogleDriveConnector extends StatefulWidget {
  const GoogleDriveConnector({
    super.key,
    required this.child,
    this.onConnectionChanged,
  });
  final Widget child;
  final Function(bool isConnected, Map<String, dynamic>? userInfo)?
  onConnectionChanged;

  @override
  State<GoogleDriveConnector> createState() => _GoogleDriveConnectorState();
}

class _GoogleDriveConnectorState extends State<GoogleDriveConnector> {
  bool _isConnected = false;
  bool _isLoading = false;
  Map<String, dynamic>? _userInfo;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkConnectionStatus();
  }

  Future<void> _checkConnectionStatus() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final service = GoogleBackupService(accessToken: null);
      final userInfo = await service.fetchUserInfoIfTokenValid();

      if (mounted) {
        setState(() {
          _isConnected = userInfo != null;
          _userInfo = userInfo;
          _errorMessage = null;
        });

        widget.onConnectionChanged?.call(_isConnected, _userInfo);
      }
    } on Exception catch (e) {
      Log.w(
        'GoogleDriveConnector: failed to check connection status: $e',
        tag: 'GoogleDrive',
      );
      if (mounted) {
        setState(() {
          _isConnected = false;
          _userInfo = null;
          _errorMessage = null; // Don't show error for initial check
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> connectToGoogleDrive() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final service = GoogleBackupService(accessToken: null);
      final tokenMap = await service.linkAccount(
        forceUseGoogleSignIn: true, // Force native chooser on Android
        scopes: [
          'openid',
          'email',
          'profile',
          'https://www.googleapis.com/auth/drive.appdata',
        ],
      );

      Log.d('GoogleDriveConnector: connection successful', tag: 'GoogleDrive');

      // Verify connection by fetching user info
      final connectedService = GoogleBackupService(
        accessToken: tokenMap['access_token'],
      );
      final userInfo = await connectedService.fetchUserInfoIfTokenValid();

      if (mounted) {
        setState(() {
          _isConnected = true;
          _userInfo = userInfo;
          _errorMessage = null;
        });

        widget.onConnectionChanged?.call(_isConnected, _userInfo);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Conectado a Google Drive como ${userInfo?['email'] ?? 'usuario'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on Exception catch (e) {
      Log.e('GoogleDriveConnector: connection failed: $e', tag: 'GoogleDrive');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _userInfo = null;
          _errorMessage = _getErrorMessage(e.toString());
        });

        widget.onConnectionChanged?.call(_isConnected, _userInfo);

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar: $_errorMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Reintentar',
              textColor: Colors.white,
              onPressed: () => connectToGoogleDrive(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> disconnectFromGoogleDrive() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final service = GoogleBackupService(accessToken: null);
      await service.clearStoredCredentials();

      if (mounted) {
        setState(() {
          _isConnected = false;
          _userInfo = null;
          _errorMessage = null;
        });

        widget.onConnectionChanged?.call(_isConnected, _userInfo);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desconectado de Google Drive'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      Log.e('GoogleDriveConnector: disconnect failed: $e', tag: 'GoogleDrive');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(final String error) {
    if (error.contains('User cancelled')) {
      return 'Conexión cancelada por el usuario';
    } else if (error.contains('network')) {
      return 'Error de conexión. Verifica tu internet.';
    } else if (error.contains('access_denied') ||
        error.contains('access blocked')) {
      return 'Acceso denegado. Verifica la configuración OAuth.';
    } else if (error.contains('invalid_client')) {
      return 'Cliente OAuth inválido. Verifica la configuración.';
    } else {
      return 'Error desconocido. Consulta los logs.';
    }
  }

  @override
  Widget build(final BuildContext context) {
    return Column(
      children: [
        if (_isLoading) const LinearProgressIndicator(),

        // Connection status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _isConnected ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isConnected
                      ? 'Google Drive: ${_userInfo?['email'] ?? 'Conectado'}'
                      : 'Google Drive: No conectado',
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
              if (!_isLoading) ...[
                if (_isConnected)
                  TextButton.icon(
                    onPressed: disconnectFromGoogleDrive,
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Desconectar'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: connectToGoogleDrive,
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Conectar'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),

        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _errorMessage = null),
                  child: const Text('OK', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

        Expanded(child: widget.child),
      ],
    );
  }
}
