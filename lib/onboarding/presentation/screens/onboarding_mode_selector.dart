import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/shared/widgets/google_drive_backup_dialog.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:math';
import 'conversational_onboarding_screen.dart';
import 'onboarding_screen.dart';

typedef OnboardingFinishCallback =
    Future<void> Function({
      required String userName,
      required String aiName,
      required DateTime? userBirthdate,
      required String meetStory,
      String? userCountryCode,
      String? aiCountryCode,
      Map<String, dynamic>? appearance,
    });

/// Pantalla de selección de modo de onboarding con conversacional por defecto
class OnboardingModeSelector extends StatefulWidget {
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;
  final OnboardingProvider? onboardingProvider;
  final ChatProvider? chatProvider;

  const OnboardingModeSelector({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
    this.onboardingProvider,
    this.chatProvider,
  });

  @override
  State<OnboardingModeSelector> createState() => _OnboardingModeSelectorState();
}

class _OnboardingModeSelectorState extends State<OnboardingModeSelector> {
  /// Construye un widget de texto con estilo consistente
  Widget _buildStyledText({
    required String text,
    required Color color,
    required double fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? height,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        height: height,
        fontFamily: 'monospace',
      ),
    );
  }

  /// Construye el título principal
  Widget _buildMainTitle() {
    return _buildStyledText(
      text: 'Iniciemos tu historia con AI-chan',
      color: AppColors.primary,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    );
  }

  /// Construye la descripción principal
  Widget _buildMainDescription() {
    return _buildStyledText(
      text:
          'Elige cómo quieres conocer a tu AI-chan: ¿Una conversación natural como en la vida real, o prefieres un formulario tradicional?',
      color: AppColors.secondary,
      fontSize: 16,
      height: 1.5,
    );
  }

  /// Construye el pie de página
  Widget _buildFooterText() {
    return _buildStyledText(
      text:
          'La conversación natural crea una experiencia más inmersiva y permite que AI-chan conozca tu personalidad de forma orgánica.',
      color: AppColors.secondary,
      fontSize: 12,
      fontStyle: FontStyle.italic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text.rich(
          TextSpan(
            text: Config.getAppName(),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          // Menú de opciones (3 puntos)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.secondary),
            color: Colors.black,
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'restore_local',
                child: Row(
                  children: [
                    Icon(Icons.restore, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      'Restaurar copia de seguridad local',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (value) async {
              if (value == 'restore_local') {
                await _handleRestoreFromLocal(context);
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0A), Color(0xFF1A0A1A), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Contenido principal centrado
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Avatar y título
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/icons/app_icon.png',
                                width: 116,
                                height: 116,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Título
                          _buildMainTitle(),

                          const SizedBox(height: 16),

                          // Descripción
                          _buildMainDescription(),

                          const SizedBox(height: 48),

                          // Botones lado a lado con estilo cyberpunk
                          Row(
                            children: [
                              // Botón conversacional
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final result = await Navigator.of(context)
                                        .push<bool>(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ConversationalOnboardingScreen(
                                                  onFinish: widget.onFinish,
                                                  onboardingProvider:
                                                      widget.onboardingProvider,
                                                ),
                                          ),
                                        );
                                    // Si completó el onboarding conversacional, la app debería continuar
                                    if (result == true && context.mounted) {
                                      // El ConversationalOnboardingScreen ya llamó a onFinish
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.mic,
                                    color: Colors.black,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.black,
                                    minimumSize: const Size(0, 56),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                  ),
                                  label: const Text(
                                    'CONVERSACIÓN',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 16),

                              // Botón formulario
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (_) => OnboardingScreen(
                                          onFinish: widget.onFinish,
                                          onClearAllDebug:
                                              widget.onClearAllDebug,
                                          onImportJson: widget.onImportJson,
                                          onboardingProvider:
                                              widget.onboardingProvider,
                                          chatProvider: widget.chatProvider,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.assignment,
                                    color: AppColors.secondary,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.secondary,
                                    side: const BorderSide(
                                      color: AppColors.secondary,
                                      width: 2,
                                    ),
                                    minimumSize: const Size(0, 56),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                  ),
                                  label: const Text(
                                    'FORMULARIO',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Pie de página
                          _buildFooterText(),
                          const SizedBox(height: 24),

                          // Botón de iniciar sesión con Google
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await _handleGoogleDriveBackup(context);
                              },
                              icon: Image.asset(
                                'assets/icons/google.png',
                                width: 20,
                                height: 20,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(0, 56),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              label: const Text(
                                'INICIAR SESIÓN CON GOOGLE',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maneja la restauración desde archivo local
  Future<void> _handleRestoreFromLocal(BuildContext context) async {
    setState(() {});
    try {
      // Usar FilePicker para seleccionar el archivo de backup
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        return; // Usuario canceló
      }

      final path = result.files.first.path;
      if (path == null) {
        return; // No se pudo obtener la ruta
      }

      final f = File(path);

      // Usar BackupService para extraer el JSON del archivo de backup
      final jsonStr = await BackupService.restoreAndExtractJson(f);

      // Importar el JSON extraído
      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
      );

      if (imported != null) {
        if (widget.onImportJson != null) {
          await widget.onImportJson!(imported);
        }
        if (mounted) {
          await showAppDialog(
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.black,
              title: const Text(
                'Restauración completada',
                style: TextStyle(color: AppColors.primary),
              ),
              content: const Text(
                'Datos restaurados correctamente.',
                style: TextStyle(color: AppColors.secondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Error en la importación
      if (mounted) {
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text(
              'Error al importar',
              style: TextStyle(color: Colors.red),
            ),
            content: const Text(
              'Error importando backup: JSON inválido',
              style: TextStyle(color: AppColors.secondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Error', style: TextStyle(color: Colors.red)),
            content: Text(
              'Error restaurando backup: $e',
              style: const TextStyle(color: AppColors.secondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Maneja el backup con Google Drive
  Future<void> _handleGoogleDriveBackup(BuildContext context) async {
    final ChatProvider? cp = widget.chatProvider;
    final OnboardingProvider? op = widget.onboardingProvider;

    final res = await showAppDialog<dynamic>(
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        content: Builder(
          builder: (ctxInner) {
            final screenWidth = MediaQuery.of(ctxInner).size.width;
            final margin = screenWidth > 800 ? 32.0 : 4.0;
            final maxWidth = screenWidth > 800 ? 900.0 : double.infinity;
            final dialogWidth = min(screenWidth - margin, maxWidth).toDouble();
            return SizedBox(
              width: dialogWidth,
              child: GoogleDriveBackupDialog(
                requestBackupJson: cp != null
                    ? () async {
                        final captured = cp;
                        return await BackupUtils.exportChatPartsToJson(
                          profile: captured.onboardingData,
                          messages: captured.messages,
                          events: captured.events,
                        );
                      }
                    : null,
                onImportedJson: cp != null
                    ? (jsonStr) async {
                        final captured = cp;
                        final imported = await chat_json_utils
                            .ChatJsonUtils.importAllFromJson(jsonStr);
                        if (imported != null) {
                          await captured.applyImportedChat(imported);
                        }
                      }
                    : null,
                onAccountInfoUpdated: cp != null
                    ? ({
                        String? email,
                        String? avatarUrl,
                        String? name,
                        bool linked = false,
                        bool triggerAutoBackup = false,
                      }) async {
                        final captured = cp;
                        await captured.updateGoogleAccountInfo(
                          email: email,
                          avatarUrl: avatarUrl,
                          name: name,
                          linked: linked,
                          triggerAutoBackup: triggerAutoBackup,
                        );
                      }
                    : null,
                onClearAccountInfo: cp != null
                    ? () => cp.clearGoogleAccountInfo()
                    : null,
              ),
            );
          },
        ),
      ),
    );

    // Si el diálogo devolvió JSON restaurado (cuando no se pasó ChatProvider), importarlo
    if (res is Map && res['restoredJson'] is String && cp == null) {
      final jsonStr = res['restoredJson'] as String;
      try {
        final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
          jsonStr,
          onError: (err) => op?.setImportError(err),
        );
        if (imported != null) {
          await op?.applyImportedChat(imported);
          if (widget.onImportJson != null) {
            await widget.onImportJson!(imported);
          }
          if (mounted) setState(() {});
        } else {
          await showAppDialog(
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.black,
              title: const Text(
                'Error al importar',
                style: TextStyle(color: Colors.red),
              ),
              content: Text(
                op?.importError ?? 'Error desconocido',
                style: const TextStyle(color: AppColors.secondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Error', style: TextStyle(color: Colors.red)),
            content: Text(
              e.toString(),
              style: const TextStyle(color: AppColors.secondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        );
      }
    }
  }
}
