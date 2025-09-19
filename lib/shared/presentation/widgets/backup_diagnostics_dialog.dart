import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ai_chan/shared.dart'; // Using shared exports for all dependencies
import 'package:ai_chan/chat/presentation/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - ChatController directo

/// Widget de diagnóstico para verificar el estado de backups automáticos y autenticación Google
class BackupDiagnosticsDialog extends StatefulWidget {
  // ✅ DDD: ETAPA 3 - Migrado a ChatController

  const BackupDiagnosticsDialog({super.key, this.chatProvider});
  final ChatController? chatProvider;

  @override
  State<BackupDiagnosticsDialog> createState() =>
      _BackupDiagnosticsDialogState();
}

class _BackupDiagnosticsDialogState extends State<BackupDiagnosticsDialog> {
  String _diagnosticResult = 'Ejecutando diagnóstico...';
  bool _isLoading = true;
  Timer? _countdownTimer;
  Map<String, dynamic>? _lastAdvancedDiagnosis;
  DateTime? _lastDiagnosisTime;
  int? _originalTokenExpiresIn; // Guardamos el valor original

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel(); // Cancelar timer anterior si existe

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (final timer) {
      if (!mounted ||
          _isLoading ||
          _lastAdvancedDiagnosis == null ||
          _originalTokenExpiresIn == null) {
        return;
      }

      // Calcular tiempo transcurrido desde el diagnóstico
      final elapsedSeconds = DateTime.now()
          .difference(_lastDiagnosisTime!)
          .inSeconds;
      final currentExpiresIn = (_originalTokenExpiresIn! - elapsedSeconds)
          .clamp(0, _originalTokenExpiresIn!);

      // Solo actualizar UI si el tiempo ha cambiado
      setState(() {
        // Actualizar el serviceStatus temporalmente para mostrar el countdown
        if (_lastAdvancedDiagnosis!['serviceStatus'] != null) {
          final serviceStatus =
              _lastAdvancedDiagnosis!['serviceStatus'] as Map<String, dynamic>;
          serviceStatus['tokenExpiresInSeconds'] = currentExpiresIn;
        }
        _diagnosticResult = _buildDiagnosticOutput();
      });

      // Detener el timer si el token ha expirado
      if (currentExpiresIn <= 0) {
        timer.cancel();
      }
    });
  }

  String _buildDiagnosticOutput() {
    if (_lastAdvancedDiagnosis == null) {
      return _diagnosticResult;
    }

    final buffer = StringBuffer();

    try {
      buffer.writeln('=== DIAGNÓSTICO GOOGLE DRIVE COMPLETO ===\n');

      // 1. OAuth Configuration Diagnostics (includes Android-specific checks)
      buffer.write(_runOAuthConfigDiagnostics());

      // 2. Diagnóstico avanzado usando ChatProvider (con countdown en tiempo real)
      final advancedDiagnosis = _lastAdvancedDiagnosis!;

      buffer.writeln('2. DIAGNÓSTICO AVANZADO DE AUTENTICACIÓN:');
      buffer.writeln(
        '   - Google Linked (ChatProvider): ${advancedDiagnosis['googleLinked']}',
      );
      buffer.writeln(
        '   - Email: ${advancedDiagnosis['chatProviderState']?['googleEmail'] ?? 'N/A'}',
      );
      buffer.writeln(
        '   - Nombre: ${advancedDiagnosis['chatProviderState']?['googleName'] ?? 'N/A'}',
      );
      buffer.writeln(
        '   - Token válido: ${advancedDiagnosis['hasValidToken']}',
      );
      buffer.writeln(
        '   - Token length: ${advancedDiagnosis['tokenLength'] ?? 'N/A'}',
      );

      // Circuit Breaker Status
      if (advancedDiagnosis['circuitBreakerStatus'] != null) {
        final cb =
            advancedDiagnosis['circuitBreakerStatus'] as Map<String, dynamic>;
        buffer.writeln('   - Circuit Breaker:');
        buffer.writeln(
          '     * Estado: ${cb['isActive'] == true ? 'ABIERTO (bloqueado)' : 'CERRADO (funcionando)'}',
        );
        buffer.writeln(
          '     * Fallos: ${cb['failures'] ?? 0}/${cb['maxFailures'] ?? 8}',
        );
        buffer.writeln(
          '     * Último fallo: ${cb['lastFailure'] ?? 'Ninguno'}',
        );
        buffer.writeln(
          '     * Cooldown: ${cb['cooldownMinutes'] ?? 15} minutos',
        );
      }

      // Android específico con countdown en tiempo real
      if (advancedDiagnosis['serviceStatus'] != null) {
        final serviceStatus =
            advancedDiagnosis['serviceStatus'] as Map<String, dynamic>;
        buffer.writeln('   - Estado Android:');
        buffer.writeln(
          '     * Credenciales almacenadas: ${serviceStatus['hasStoredCredentials']}',
        );
        buffer.writeln(
          '     * Refresh token: ${serviceStatus['hasRefreshToken']}',
        );
        buffer.writeln(
          '     * Access token: ${serviceStatus['hasAccessToken']}',
        );
        buffer.writeln(
          '     * Token expira en: ${serviceStatus['tokenExpiresInSeconds']}s ⏱️',
        );
        buffer.writeln(
          '     * Native SignIn: ${serviceStatus['nativeSignInStatus']}',
        );
      }
      buffer.writeln();

      // Agregar el resto del diagnóstico original aquí (si existe)
      // Por simplicidad, se puede agregar más contenido según sea necesario
    } on Exception catch (e) {
      buffer.writeln('Error generando diagnóstico actualizado: $e');
    }

    return buffer.toString();
  }

  /// Unified OAuth configuration diagnostics (includes Android-specific checks)
  String _runOAuthConfigDiagnostics() {
    final buffer = StringBuffer();

    buffer.writeln('1. CONFIGURACIÓN OAUTH:');

    // Check client IDs
    final androidClientId = Config.get('GOOGLE_CLIENT_ID_ANDROID', '').trim();
    final webClientId = Config.get('GOOGLE_CLIENT_ID_WEB', '').trim();
    final webClientSecret = Config.get('GOOGLE_CLIENT_SECRET_WEB', '').trim();

    buffer.writeln(
      '   📱 Android Client ID: ${androidClientId.isEmpty ? '❌ MISSING' : '✅ Present (${androidClientId.length} chars)'}',
    );
    buffer.writeln(
      '   🌐 Web Client ID: ${webClientId.isEmpty ? '❌ MISSING' : '✅ Present (${webClientId.length} chars)'}',
    );
    buffer.writeln(
      '   🔐 Web Client Secret: ${webClientSecret.isEmpty ? '❌ MISSING' : '✅ Present (${webClientSecret.length} chars)'}',
    );

    // Check if they end with correct suffixes
    if (androidClientId.isNotEmpty) {
      const expectedSuffix = '.apps.googleusercontent.com';
      if (androidClientId.endsWith(expectedSuffix)) {
        buffer.writeln('   ✅ Android Client ID has correct suffix');
      } else {
        buffer.writeln(
          '   ⚠️  Android Client ID should end with $expectedSuffix',
        );
      }
    }

    if (webClientId.isNotEmpty) {
      const expectedSuffix = '.apps.googleusercontent.com';
      if (webClientId.endsWith(expectedSuffix)) {
        buffer.writeln('   ✅ Web Client ID has correct suffix');
      } else {
        buffer.writeln('   ⚠️  Web Client ID should end with $expectedSuffix');
      }
    }

    // Platform-specific checks
    if (!kIsWeb && Platform.isAndroid) {
      buffer.writeln('   🤖 Platform: Android');
      buffer.writeln('   🔄 Refresh Token Requirements:');
      buffer.writeln(
        '     1. Android Client ID configured: ${androidClientId.isNotEmpty ? '✅' : '❌'}',
      );
      buffer.writeln(
        '     2. Web Client ID configured: ${webClientId.isNotEmpty ? '✅' : '❌'}',
      );
      buffer.writeln(
        '     3. Web Client Secret configured: ${webClientSecret.isNotEmpty ? '✅' : '❌'}',
      );
      buffer.writeln(
        '     4. AndroidManifest intent-filter: 🤔 (check manually)',
      );
      buffer.writeln('     5. Google Cloud Console SHA-1: 🤔 (check manually)');

      // Summary for Android
      final allConfigured =
          androidClientId.isNotEmpty &&
          webClientId.isNotEmpty &&
          webClientSecret.isNotEmpty;
      if (allConfigured) {
        buffer.writeln('   ✅ OAuth configuration looks good for Android');
      } else {
        buffer.writeln(
          '   ❌ OAuth configuration incomplete - refresh tokens may not work',
        );
      }
    } else if (!kIsWeb) {
      buffer.writeln('   🖥️  Platform: Desktop');
      buffer.writeln('   ✅ Desktop OAuth typically works well');
    } else {
      buffer.writeln('   🌐 Platform: Web');
    }

    buffer.writeln();
    return buffer.toString();
  }

  /// Corrige el tiempo de expiración del token basado en la fecha real de creación
  Future<int?> _correctTokenExpirationTime(final int reportedSeconds) async {
    try {
      const storage = FlutterSecureStorage();
      final credsStr = await storage.read(key: 'google_credentials');

      if (credsStr != null && credsStr.isNotEmpty) {
        final creds = jsonDecode(credsStr) as Map<String, dynamic>;
        final persistedAtMs = (creds['_persisted_at_ms'] as int?) ?? 0;
        final expiresIn = (creds['expires_in'] as int?) ?? 3600;

        if (persistedAtMs > 0) {
          final tokenCreationTime = DateTime.fromMillisecondsSinceEpoch(
            persistedAtMs,
          );
          final tokenExpiryTime = tokenCreationTime.add(
            Duration(seconds: expiresIn),
          );
          final now = DateTime.now();
          final realRemainingSeconds = tokenExpiryTime
              .difference(now)
              .inSeconds
              .clamp(0, expiresIn);

          // Sistema de corrección de tiempo funcionando correctamente

          return realRemainingSeconds;
        }
      }
    } on Exception {
      // Error en corrección de tiempo, usar valor original
    }
    return null; // Si no se puede corregir, usar el tiempo original
  }

  Future<void> _runDiagnostics() async {
    final buffer = StringBuffer();

    try {
      buffer.writeln('=== DIAGNÓSTICO GOOGLE DRIVE COMPLETO ===\n');

      // 1. OAuth Configuration Diagnostics (includes Android-specific checks)
      buffer.write(_runOAuthConfigDiagnostics());

      // 2. Diagnóstico avanzado usando ChatProvider (si está disponible)
      if (mounted && widget.chatProvider != null) {
        try {
          final chatProvider = widget.chatProvider!;
          final advancedDiagnosis = await chatProvider.googleController
              .diagnoseGoogleState();

          // Guardar datos para el countdown en tiempo real
          _lastAdvancedDiagnosis = advancedDiagnosis;
          _lastDiagnosisTime = DateTime.now();

          // Guardar el valor original del token si existe
          if (advancedDiagnosis['serviceStatus'] != null) {
            final serviceStatus =
                advancedDiagnosis['serviceStatus'] as Map<String, dynamic>;
            final reportedSeconds =
                serviceStatus['tokenExpiresInSeconds'] as int?;

            // 🔧 Usar tiempo corregido para el countdown también
            if (reportedSeconds != null) {
              final correctedSeconds = await _correctTokenExpirationTime(
                reportedSeconds,
              );
              _originalTokenExpiresIn = correctedSeconds ?? reportedSeconds;
            }
          }

          buffer.writeln('2. DIAGNÓSTICO AVANZADO DE AUTENTICACIÓN:');
          buffer.writeln(
            '   - Google Linked (ChatProvider): ${advancedDiagnosis['googleLinked']}',
          );
          buffer.writeln(
            '   - Email: ${advancedDiagnosis['chatProviderState']?['googleEmail'] ?? 'N/A'}',
          );
          buffer.writeln(
            '   - Nombre: ${advancedDiagnosis['chatProviderState']?['googleName'] ?? 'N/A'}',
          );
          buffer.writeln(
            '   - Token válido: ${advancedDiagnosis['hasValidToken']}',
          );
          buffer.writeln(
            '   - Token length: ${advancedDiagnosis['tokenLength'] ?? 'N/A'}',
          );

          // Circuit Breaker Status
          if (advancedDiagnosis['circuitBreakerStatus'] != null) {
            final cb =
                advancedDiagnosis['circuitBreakerStatus']
                    as Map<String, dynamic>;
            buffer.writeln('   - Circuit Breaker:');
            buffer.writeln(
              '     * Estado: ${cb['isActive'] == true ? 'ABIERTO (bloqueado)' : 'CERRADO (funcionando)'}',
            );
            buffer.writeln(
              '     * Fallos: ${cb['failures'] ?? 0}/${cb['maxFailures'] ?? 8}',
            );
            buffer.writeln(
              '     * Último fallo: ${cb['lastFailure'] ?? 'Ninguno'}',
            );
            buffer.writeln(
              '     * Cooldown: ${cb['cooldownMinutes'] ?? 15} minutos',
            );
          }

          // Android específico
          if (advancedDiagnosis['serviceStatus'] != null) {
            final serviceStatus =
                advancedDiagnosis['serviceStatus'] as Map<String, dynamic>;

            // 🔧 Corregir el tiempo de expiración basado en la fecha real de creación
            final reportedSeconds =
                serviceStatus['tokenExpiresInSeconds'] as int? ?? 0;
            final correctedSeconds = await _correctTokenExpirationTime(
              reportedSeconds,
            );
            final displaySeconds = correctedSeconds ?? reportedSeconds;

            buffer.writeln('   - Estado Android:');
            buffer.writeln(
              '     * Credenciales almacenadas: ${serviceStatus['hasStoredCredentials']}',
            );
            buffer.writeln(
              '     * Refresh token: ${serviceStatus['hasRefreshToken']}',
            );
            buffer.writeln(
              '     * Access token: ${serviceStatus['hasAccessToken']}',
            );
            buffer.writeln('     * Token expira en: ${displaySeconds}s ⏱️');
            buffer.writeln(
              '     * Native SignIn: ${serviceStatus['nativeSignInStatus']}',
            );
          }
          buffer.writeln();
        } on Exception catch (e) {
          buffer.writeln('2. ERROR EN DIAGNÓSTICO AVANZADO: $e\n');
        }
      }

      // 3. Diagnóstico básico (mantenido por compatibilidad)
      buffer.writeln('3. Información básica de cuenta Google:');
      final googleInfo = await PrefsUtils.getGoogleAccountInfo();
      buffer.writeln('   - Email: ${googleInfo['email'] ?? 'No configurado'}');
      buffer.writeln('   - Name: ${googleInfo['name'] ?? 'No configurado'}');
      buffer.writeln('   - Linked: ${googleInfo['linked'] ?? false}');

      // 4. Verificar token usando método pasivo para evitar activar OAuth
      buffer.writeln('\n4. Token de acceso:');
      final service = GoogleBackupService();
      final token = await service.loadStoredAccessTokenPassive();
      final hasToken = token != null && token.isNotEmpty;
      buffer.writeln('   - Token presente: $hasToken');
      if (hasToken) {
        buffer.writeln('   - Token length: ${token.length}');
        buffer.writeln(
          '   - Válido: ${token.startsWith('ya29.') ? 'Probablemente sí' : 'Formato inusual'}',
        );
      }

      // 5. Último backup
      buffer.writeln('\n5. Último backup automático:');
      final lastBackupMs = await PrefsUtils.getLastAutoBackupMs();
      if (lastBackupMs != null) {
        final lastBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupMs);
        final now = DateTime.now();
        final diff = now.difference(lastBackup);
        buffer.writeln('   - Fecha: ${lastBackup.toString()}');
        buffer.writeln('   - Hace: ${diff.inHours}h ${diff.inMinutes % 60}m');
        buffer.writeln('   - Requiere nuevo backup: ${diff.inHours > 24}');
      } else {
        buffer.writeln('   - Nunca se ha ejecutado backup automático');
      }

      // 6. Verificar backups remotos
      if (hasToken) {
        buffer.writeln('\n6. Backups remotos:');
        try {
          final serviceWithToken = GoogleBackupService(accessToken: token);
          final backups = await serviceWithToken.listBackups();
          buffer.writeln('   - Cantidad encontrada: ${backups.length}');
          if (backups.isNotEmpty) {
            final latest = backups.first;
            buffer.writeln(
              '   - Último: ${latest['name']} (${latest['createdTime']})',
            );
          }
        } on Exception catch (e) {
          buffer.writeln('   - Error: $e');
        }
      } else {
        buffer.writeln(
          '\n6. Backups remotos: No se puede verificar (sin token)',
        );
      }

      // 7. Diagnóstico final
      buffer.writeln('\n=== DIAGNÓSTICO FINAL ===');
      final googleLinked = googleInfo['linked'] as bool? ?? false;
      final needsBackup =
          lastBackupMs == null ||
          (DateTime.now().millisecondsSinceEpoch - lastBackupMs) >
              const Duration(hours: 24).inMilliseconds;

      if (googleLinked && !hasToken) {
        buffer.writeln('⚠️  PROBLEMA DETECTADO:');
        buffer.writeln(
          '   Cuenta marcada como vinculada pero sin token válido.',
        );
        buffer.writeln('   Los backups automáticos fallarán silenciosamente.');
        buffer.writeln('   SOLUCIÓN: Re-vincular cuenta en configuración.');
      } else if (googleLinked && hasToken && needsBackup) {
        buffer.writeln('✅ CONFIGURACIÓN CORRECTA:');
        buffer.writeln('   Debería ejecutarse backup automático pronto.');
      } else if (!googleLinked) {
        buffer.writeln('ℹ️  Google Drive no vinculado.');
        buffer.writeln('   Los backups automáticos están deshabilitados.');
      } else {
        buffer.writeln('✅ Backup reciente encontrado.');
        buffer.writeln('   No se necesita backup automático ahora.');
      }
    } on Exception catch (e) {
      buffer.writeln('❌ Error durante diagnóstico: $e');
    }

    if (mounted) {
      setState(() {
        _diagnosticResult = buffer.toString();
        _isLoading = false;
      });

      // Iniciar el countdown timer si tenemos datos de token
      if (_originalTokenExpiresIn != null && _originalTokenExpiresIn! > 0) {
        _startCountdownTimer();
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black,
      title: const Text(
        'GOOGLE DRIVE DIAGNOSTICS // グーグルドライブシンダン',
        style: TextStyle(
          color: Color(0xFF00FFAA),
          fontFamily: 'monospace',
          fontSize: 16,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: SingleChildScrollView(
          child: _isLoading
              ? const CyberpunkLoader(
                  message: 'SCANNING BACKUP SYSTEMS...',
                  showProgressBar: true,
                )
              : SelectableText(
                  _diagnosticResult,
                  style: const TextStyle(
                    color: Color(0xFF00FFAA),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'CLOSE',
            style: TextStyle(color: Color(0xFF00FFAA)),
          ),
        ),
        TextButton(
          onPressed: () async {
            setState(() {
              _isLoading = true;
            });
            await _runDiagnostics();
          },
          child: const Text(
            'REFRESH',
            style: TextStyle(color: Color(0xFF00FFAA)),
          ),
        ),
        // 🧪 DEBUG: Test token refresh button
        TextButton(
          onPressed: () async {
            setState(() {
              _isLoading = true;
              _diagnosticResult =
                  '🧪 TESTING: Iniciando test detallado de refresh...\n';
            });

            try {
              // Create service instance for testing
              final service = GoogleBackupService();

              // Use the new detailed diagnostics method
              final diagnosticResult = await service
                  .forceTokenAgeAndRefreshWithDiagnostics();

              // Display the detailed step-by-step results
              final steps = (diagnosticResult['steps'] as List<String>);
              for (final step in steps) {
                setState(() {
                  _diagnosticResult += '$step\n';
                });
              }

              final success = diagnosticResult['success'] as bool? ?? false;
              setState(() {
                _diagnosticResult += '\n═══════════════════════════════\n';
                _diagnosticResult +=
                    'RESULTADO FINAL: ${success ? '✅ ÉXITO' : '❌ FALLO'}\n';

                if (diagnosticResult['error'] != null) {
                  _diagnosticResult += 'Error: ${diagnosticResult['error']}\n';
                }

                _diagnosticResult += '\n📊 INFORMACIÓN DE PLATAFORMA:\n';
                _diagnosticResult +=
                    '• Plataforma: ${diagnosticResult['platformDetected'] ?? 'desconocida'}\n';
                _diagnosticResult +=
                    '• Client ID original: ${diagnosticResult['originalClientId'] ?? 0} caracteres\n';
                _diagnosticResult +=
                    '• Client Secret: ${diagnosticResult['clientSecretLength'] ?? 0} caracteres\n';

                if (diagnosticResult['finalToken'] != null) {
                  _diagnosticResult +=
                      '• Nuevo token: ${diagnosticResult['finalToken']}...\n';
                }

                if (success) {
                  _diagnosticResult +=
                      '\n🎉 ¡ANDROID OAUTH FIX FUNCIONANDO CORRECTAMENTE!\n';
                } else {
                  _diagnosticResult +=
                      '\n💡 Consulta los logs de consola para más detalles\n';
                }
              });
            } on Exception catch (e) {
              setState(() {
                _diagnosticResult += '❌ Test failed with error: $e\n';
                _diagnosticResult +=
                    '💡 Esto normalmente indica un problema de OAuth\n';
                _diagnosticResult +=
                    '📱 Esperado en Android debido al mismatch de credenciales web\n';
              });
            }

            setState(() {
              _isLoading = false;
            });
          },
          child: const Text(
            '🧪 TEST REFRESH',
            style: TextStyle(color: Color(0xFFFF6B6B)),
          ),
        ),
      ],
    );
  }
}
