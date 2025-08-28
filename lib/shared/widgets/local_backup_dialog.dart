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
        if (navCtx != null && mounted) showAppSnackBar(msg, preferRootMessenger: true);
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
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
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
    return SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Row(
                children: [
                  Icon(Icons.sd_storage, size: 20, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Copia de seguridad local', style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: 'Cerrar',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_status != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(_status!, style: const TextStyle(color: Colors.white70)),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: (_working || widget.requestExportJson == null) ? null : _doCreateBackup,
                icon: const Icon(Icons.save_alt),
                label: const Text('Guardar archivo de copia de seguridad'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _working ? null : _doRestoreFromFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Restaurar desde archivo'),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}
