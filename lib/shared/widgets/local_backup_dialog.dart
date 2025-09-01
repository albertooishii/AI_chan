import 'dart:io';

import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart' show showAppSnackBar;
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
// provider not required here; ChatProvider is passed in directly
import 'package:ai_chan/main.dart' show navigatorKey;
import 'package:ai_chan/core/models.dart';

class LocalBackupDialog extends StatefulWidget {
  // Callback that returns the JSON string to export. If null, export UI is disabled.
  final Future<String> Function()? requestExportJson;
  // Callback invoked when an ImportedChat is available after a restore.
  final Future<void> Function(ImportedChat imported)? onImportedJson;
  // Optional error callback for parse errors.
  final void Function(String error)? onImportError;

  const LocalBackupDialog({super.key, this.requestExportJson, this.onImportedJson, this.onImportError});

  @override
  State<LocalBackupDialog> createState() => _LocalBackupDialogState();
}

class _LocalBackupDialogState extends State<LocalBackupDialog> {
  String? _status;
  bool _working = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _doCreateBackup() async {
    setState(() => _working = true);
    try {
      // Ask for optional directory selection on platforms that support it
      String? selectedDir;
      var directoryPickerSupported = true;
      try {
        selectedDir = await FilePicker.platform.getDirectoryPath();
      } catch (_) {
        directoryPickerSupported = false;
      }
      if (directoryPickerSupported && selectedDir == null) {
        // user cancelled
        _safeSetState(() => _working = false);
        return;
      }
      if (widget.requestExportJson == null) throw 'No export callback provided';
      final jsonStr = await widget.requestExportJson!.call();
      final file = await BackupService.createLocalBackup(jsonStr: jsonStr, destinationDirPath: selectedDir);
      final msg = 'Backup creado: ${file.path}';
      try {
        final navCtx = navigatorKey.currentContext;
        if (navCtx != null && mounted) {
          showAppSnackBar(msg, preferRootMessenger: true);
        }
      } catch (_) {}
      _safeSetState(() {
        _status = msg;
        _working = false;
      });
    } catch (e) {
      _safeSetState(() {
        _status = 'Error creando backup: $e';
        _working = false;
      });
    }
  }

  Future<void> _doRestoreFromFile() async {
    setState(() => _working = true);
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        _safeSetState(() => _working = false);
        return;
      }
      final path = result.files.first.path;
      if (path == null) {
        _safeSetState(() => _working = false);
        return;
      }
      final f = File(path);
      final jsonStr = await BackupService.restoreAndExtractJson(f);
      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(jsonStr);
      if (imported != null) {
        if (widget.onImportedJson != null) {
          await widget.onImportedJson!.call(imported);
        }
        try {
          if (!mounted) return;
          if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
        } catch (_) {}
        return;
      }
      // Notify caller of parse error if provided
      if (widget.onImportError != null) {
        widget.onImportError!('Error importando backup: JSON inválido');
      }
      _safeSetState(() {
        _status = 'Error importando backup';
        _working = false;
      });
    } catch (e) {
      _safeSetState(() {
        _status = 'Error restaurando backup: $e';
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      const Icon(Icons.sd_storage, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'LOCAL_BACKUP_INTERFACE // ローカルストレージカンリ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                          // Allow the title to wrap into multiple lines instead of truncating with ellipsis
                        ),
                      ),
                      IconButton(
                        onPressed: _working ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20), // Más espacio después del header
                // Descripción del diálogo
                const Padding(
                  padding: EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    '[LOCAL_STORAGE] // Gestión de archivos locales del dispositivo',
                    style: TextStyle(color: Colors.white70, fontSize: 15, fontFamily: 'monospace'),
                  ),
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: Text(_status!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                      ),
                    ),
                  ),
                const SizedBox(height: 16), // Más espacio antes de los botones
                // Layout inteligente y responsivo de botones
                LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;

                    // Crear botones con el mismo estilo que el diálogo de Google Drive
                    final saveButton = ElevatedButton(
                      onPressed: (_working || widget.requestExportJson == null) ? null : _doCreateBackup,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48), // Botones más altos
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text(
                        'SAVE_DATA',
                        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      ),
                    );

                    final restoreButton = ElevatedButton(
                      onPressed: _working ? null : _doRestoreFromFile,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48), // Botones más altos
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text(
                        'RESTORE_DATA',
                        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      ),
                    );

                    // Layout muy estrecho: botones apilados verticalmente
                    if (availableWidth < 500) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: double.infinity, child: saveButton),
                          const SizedBox(height: 12),
                          SizedBox(width: double.infinity, child: restoreButton),
                        ],
                      );
                    }

                    // Layout ancho: botones en la misma fila
                    return Wrap(spacing: 12.0, runSpacing: 8.0, children: [saveButton, restoreButton]);
                  },
                ),
                const SizedBox(height: 12), // Espacio final más generoso
              ],
            ),
          ),
        );
      },
    );
  }
}
