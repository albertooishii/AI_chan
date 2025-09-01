import 'package:flutter/material.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

/// Widget de diagnóstico para verificar el estado de backups automáticos
class BackupDiagnosticsDialog extends StatefulWidget {
  const BackupDiagnosticsDialog({super.key});

  @override
  State<BackupDiagnosticsDialog> createState() => _BackupDiagnosticsDialogState();
}

class _BackupDiagnosticsDialogState extends State<BackupDiagnosticsDialog> {
  String _diagnosticResult = 'Ejecutando diagnóstico...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    final buffer = StringBuffer();

    try {
      buffer.writeln('=== DIAGNÓSTICO BACKUP AUTOMÁTICO ===\n');

      // 1. Verificar información de cuenta Google
      buffer.writeln('1. Información de cuenta Google:');
      final googleInfo = await PrefsUtils.getGoogleAccountInfo();
      buffer.writeln('   - Email: ${googleInfo['email'] ?? 'No configurado'}');
      buffer.writeln('   - Name: ${googleInfo['name'] ?? 'No configurado'}');
      buffer.writeln('   - Linked: ${googleInfo['linked'] ?? false}');

      // 2. Verificar token
      buffer.writeln('\n2. Token de acceso:');
      final service = GoogleBackupService(accessToken: null);
      final token = await service.loadStoredAccessToken();
      final hasToken = token != null && token.isNotEmpty;
      buffer.writeln('   - Token presente: $hasToken');
      if (hasToken) {
        buffer.writeln('   - Token length: ${token.length}');
        buffer.writeln('   - Válido: ${token.startsWith('ya29.') ? 'Probablemente sí' : 'Formato inusual'}');
      }

      // 3. Último backup
      buffer.writeln('\n3. Último backup automático:');
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

      // 4. Verificar backups remotos
      if (hasToken) {
        buffer.writeln('\n4. Backups remotos:');
        try {
          final serviceWithToken = GoogleBackupService(accessToken: token);
          final backups = await serviceWithToken.listBackups();
          buffer.writeln('   - Cantidad encontrada: ${backups.length}');
          if (backups.isNotEmpty) {
            final latest = backups.first;
            buffer.writeln('   - Último: ${latest['name']} (${latest['createdTime']})');
          }
        } catch (e) {
          buffer.writeln('   - Error: $e');
        }
      } else {
        buffer.writeln('\n4. Backups remotos: No se puede verificar (sin token)');
      }

      // 5. Diagnóstico final
      buffer.writeln('\n=== DIAGNÓSTICO FINAL ===');
      final googleLinked = googleInfo['linked'] as bool? ?? false;
      final needsBackup =
          lastBackupMs == null ||
          (DateTime.now().millisecondsSinceEpoch - lastBackupMs) > const Duration(hours: 24).inMilliseconds;

      if (googleLinked && !hasToken) {
        buffer.writeln('⚠️  PROBLEMA DETECTADO:');
        buffer.writeln('   Cuenta marcada como vinculada pero sin token válido.');
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
    } catch (e) {
      buffer.writeln('❌ Error durante diagnóstico: $e');
    }

    if (mounted) {
      setState(() {
        _diagnosticResult = buffer.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black,
      title: const Text(
        'BACKUP_DIAGNOSTICS // バックアップシンダン',
        style: TextStyle(color: Color(0xFF00FFAA), fontFamily: 'monospace', fontSize: 16),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: SingleChildScrollView(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SelectableText(
                  _diagnosticResult,
                  style: const TextStyle(color: Color(0xFF00FFAA), fontFamily: 'monospace', fontSize: 12),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CLOSE', style: TextStyle(color: Color(0xFF00FFAA))),
        ),
        TextButton(
          onPressed: () async {
            setState(() {
              _isLoading = true;
            });
            await _runDiagnostics();
          },
          child: const Text('REFRESH', style: TextStyle(color: Color(0xFF00FFAA))),
        ),
      ],
    );
  }
}
