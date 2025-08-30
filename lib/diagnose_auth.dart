import 'package:flutter/material.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Función de diagnóstico para verificar el estado de autenticación de Google
/// Solo para desarrollo y debugging
Future<void> diagnoseGoogleAuth() async {
  final service = GoogleBackupService(accessToken: null);

  Log.d('=== DIAGNÓSTICO DE AUTENTICACIÓN GOOGLE ===', tag: 'GoogleAuth');

  try {
    // 1. Verificar credenciales almacenadas
    final diagnosis = await service.diagnoseStoredCredentials();
    Log.d('📊 Estado de credenciales almacenadas:', tag: 'GoogleAuth');
    diagnosis.forEach((key, value) {
      Log.d('   $key: $value', tag: 'GoogleAuth');
    });

    // 2. Verificar si hay access_token válido
    final accessToken = await service.loadStoredAccessToken();
    Log.d(
      '🔑 Access token: ${accessToken != null ? "Presente" : "Ausente"}',
      tag: 'GoogleAuth',
    );

    // 3. Intentar obtener info de usuario si hay token
    if (accessToken != null) {
      Log.d('👤 Probando acceso a userinfo...', tag: 'GoogleAuth');
      try {
        final userInfo = await service.fetchUserInfoIfTokenValid();
        if (userInfo != null) {
          Log.d(
            '   ✅ Userinfo obtenida: ${userInfo['email']}',
            tag: 'GoogleAuth',
          );
        } else {
          Log.d('   ❌ No se pudo obtener userinfo', tag: 'GoogleAuth');
        }
      } catch (e) {
        Log.d('   ❌ Error obteniendo userinfo: $e', tag: 'GoogleAuth');
      }
    }
  } catch (e) {
    Log.e('Error en diagnóstico', tag: 'GoogleAuth', error: e);
  }

  Log.d('=== FIN DEL DIAGNÓSTICO ===', tag: 'GoogleAuth');
}

/// Función para limpiar completamente todas las credenciales almacenadas
/// ¡USAR CON CUIDADO! Esto borrará la sesión actual
Future<void> clearAllGoogleCredentials() async {
  Log.w('LIMPIANDO TODAS LAS CREDENCIALES DE GOOGLE...', tag: 'GoogleAuth');

  try {
    final service = GoogleBackupService(accessToken: null);
    await service.clearStoredCredentials();
    Log.i('✅ Credenciales limpiadas exitosamente', tag: 'GoogleAuth');
    Log.i(
      '🔄 La próxima vez que uses Google Drive se solicitará autenticación completa',
      tag: 'GoogleAuth',
    );
  } catch (e) {
    Log.e('Error limpiando credenciales', tag: 'GoogleAuth', error: e);
  }

  Log.d('=== LIMPIEZA COMPLETADA ===', tag: 'GoogleAuth');
}

/// Widget de diagnóstico para debugging
class GoogleAuthDiagnosticWidget extends StatefulWidget {
  const GoogleAuthDiagnosticWidget({super.key});

  @override
  State<GoogleAuthDiagnosticWidget> createState() =>
      _GoogleAuthDiagnosticWidgetState();
}

class _GoogleAuthDiagnosticWidgetState
    extends State<GoogleAuthDiagnosticWidget> {
  Map<String, dynamic>? _diagnosis;
  bool _loading = false;
  String? _userEmail;

  Future<void> _runDiagnosis() async {
    setState(() {
      _loading = true;
      _diagnosis = null;
      _userEmail = null;
    });

    try {
      final service = GoogleBackupService(accessToken: null);
      final diagnosis = await service.diagnoseStoredCredentials();

      String? userEmail;
      if (diagnosis['has_access_token'] == true) {
        try {
          final userInfo = await service.fetchUserInfoIfTokenValid();
          userEmail = userInfo?['email'] as String?;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _diagnosis = diagnosis;
          _userEmail = userEmail;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error en diagnóstico: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _clearCredentials() async {
    setState(() {
      _loading = true;
    });

    try {
      await clearAllGoogleCredentials();
      if (mounted) {
        setState(() {
          _diagnosis = null;
          _userEmail = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credenciales limpiadas exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error limpiando credenciales: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico Google Auth')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton(
                onPressed: _runDiagnosis,
                child: const Text('Ejecutar Diagnóstico'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _clearCredentials,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  'Limpiar Credenciales',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              if (_diagnosis != null) ...[
                const Text(
                  'Estado de Credenciales:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._diagnosis!.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${entry.key}: ${entry.value}'),
                  ),
                ),
                if (_userEmail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Usuario: $_userEmail',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
