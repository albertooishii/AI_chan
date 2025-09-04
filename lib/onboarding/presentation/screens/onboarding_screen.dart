import 'package:ai_chan/core/presentation/widgets/cyberpunk_button.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import '../widgets/birth_date_field.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'dart:math';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/shared/widgets/google_drive_backup_dialog.dart';
import 'package:ai_chan/shared/widgets/country_autocomplete.dart';
import 'package:ai_chan/shared/widgets/female_name_autocomplete.dart';
import 'package:ai_chan/onboarding/application/controllers/form_onboarding_controller.dart';
import 'conversational_onboarding_screen.dart';

/// Callback typedef para finalizar el onboarding
typedef OnboardingFinishCallback =
    Future<void> Function({
      required String userName,
      required String aiName,
      required DateTime userBirthday,
      required String meetStory,
      String? userCountryCode,
      String? aiCountryCode,
      Map<String, dynamic>? appearance,
    });

class OnboardingScreen extends StatefulWidget {
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;
  // Optional external provider instance (presentation widgets should avoid creating providers internally when possible)
  final OnboardingProvider? onboardingProvider;
  // Optional ChatProvider instance so presentation widgets receive it via constructor
  // instead of depending on provider package APIs internally.
  final ChatProvider? chatProvider;

  const OnboardingScreen({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
    this.onboardingProvider,
    this.chatProvider,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  OnboardingProvider? _createdProvider;

  @override
  void initState() {
    super.initState();
    // If no external provider was supplied, create one and retain it across rebuilds.
    if (widget.onboardingProvider == null) {
      _createdProvider = OnboardingProvider();
    }
  }

  @override
  void dispose() {
    try {
      // Only dispose if we created it here.
      _createdProvider?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProvider = widget.onboardingProvider ?? _createdProvider!;
    // The onboarding provider instance is passed explicitly to the presentation
    // content. Presentation widgets must not call provider package APIs directly.
    return _OnboardingScreenContent(
      onboardingProvider: effectiveProvider,
      chatProvider: widget.chatProvider,
      onFinish: widget.onFinish,
      onClearAllDebug: widget.onClearAllDebug,
      onImportJson: widget.onImportJson,
    );
  }
}

class _OnboardingScreenContent extends StatefulWidget {
  // does not call provider package APIs internally.
  final OnboardingProvider onboardingProvider;
  // Optional chat provider instance passed from the parent to avoid Provider.of inside presentation.
  final ChatProvider? chatProvider;
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;

  const _OnboardingScreenContent({
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
    required this.onboardingProvider,
    this.chatProvider,
  });

  @override
  State<_OnboardingScreenContent> createState() =>
      _OnboardingScreenContentState();
}

class _OnboardingScreenContentState extends State<_OnboardingScreenContent> {
  // Clean Architecture: Controller para manejar lógica de negocio
  late final FormOnboardingController _formController;

  // Persisted Google account fallback (removed: menu now shows a static entry)

  // Subtítulo con divisor para secciones (estilo sutil)
  Widget _sectionHeader(String title, {IconData? icon}) {
    final subtleColor = AppColors.secondary.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: subtleColor),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: TextStyle(
                  color: subtleColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Clean Architecture: Use FormOnboardingController instead of inline logic
  Future<void> _handleImportJson(OnboardingProvider provider) async {
    final success = await _formController.importFromJson();

    if (success && _formController.importedData != null) {
      if (widget.onImportJson != null) {
        await widget.onImportJson!(_formController.importedData!);
      }
    } else if (_formController.hasError) {
      await showAppDialog(
        builder: (ctx) => AlertDialog(
          title: const Text('Error al importar'),
          content: Text(_formController.errorMessage!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // Clean Architecture: Use FormOnboardingController for backup restoration
  Future<void> _handleRestoreFromLocal(OnboardingProvider provider) async {
    final success = await _formController.restoreFromLocalBackup();

    if (success && _formController.importedData != null) {
      if (widget.onImportJson != null) {
        await widget.onImportJson!(_formController.importedData!);
      } else {
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            title: const Text('Restauración completada'),
            content: const Text('Biografía, imágenes y audios restaurados.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) setState(() {});
      }
    } else if (_formController.hasError) {
      await showAppDialog(
        builder: (ctx) => AlertDialog(
          title: const Text('Error al restaurar'),
          content: Text(_formController.errorMessage!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  bool get _formCompleto {
    final provider = widget.onboardingProvider;
    return provider.userNameController.text.trim().isNotEmpty &&
        (provider.aiNameController?.text.trim().isNotEmpty ?? false) &&
        provider.userBirthday != null &&
        provider.meetStoryController.text.trim().isNotEmpty &&
        (provider.userCountryCode?.trim().isNotEmpty ?? false) &&
        (provider.aiCountryCode?.trim().isNotEmpty ?? false);
  }

  late final TextEditingController _userNameController;

  @override
  void initState() {
    super.initState();
    // Clean Architecture: Initialize controller
    _formController = FormOnboardingController();
    _userNameController = TextEditingController(
      text: widget.onboardingProvider.userNameController.text,
    );
    // Register a listener to refresh the UI whenever the provider notifies listeners.
    widget.onboardingProvider.addListener(_onProviderChanged);
    // No preload persisted Google account info: menu shows a static label now.
  }

  @override
  void dispose() {
    widget.onboardingProvider.removeListener(_onProviderChanged);
    _userNameController.dispose();
    _formController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.onboardingProvider;
    void onMeetStoryChanged(String value) {
      provider.setMeetStory(value);
      setState(() {}); // Fuerza refresco para reactivar el botón
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
          // Botón para volver al modo conversacional (arriba a la izquierda del menú)
          TextButton.icon(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ConversationalOnboardingScreen(
                    onFinish: widget.onFinish,
                    onboardingProvider: widget.onboardingProvider,
                  ),
                ),
              );
              // Si completó el onboarding conversacional, no necesitamos hacer nada más
              if (result == true && mounted) {
                // El onboarding conversacional ya llamó a onFinish
              }
            },
            icon: const Icon(Icons.mic, color: AppColors.primary, size: 16),
            label: const Text(
              'Conversacional',
              style: TextStyle(color: AppColors.primary, fontSize: 12),
            ),
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              items.add(
                const PopupMenuItem<String>(
                  value: 'restore_local',
                  child: Row(
                    children: [
                      Icon(Icons.file_upload, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Restaurar desde archivo local',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              );
              // ChatProvider may be provided by the parent; we don't read it here.
              // Render a single menu entry that resolves the persisted prefs
              // at menu-open time; if a ChatProvider is provided prefer its
              // runtime values which are authoritative.
              items.add(
                const PopupMenuItem<String>(
                  value: 'backup_status',
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_to_drive,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Copia de seguridad en Google Drive',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              );
              return items;
            },
            onSelected: (value) async {
              if (value == 'backup_status') {
                final ChatProvider? cp = widget.chatProvider;
                final op = provider;
                final res = await showAppDialog<dynamic>(
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: Builder(
                      builder: (ctxInner) {
                        final screenWidth = MediaQuery.of(ctxInner).size.width;
                        final margin = screenWidth > 800 ? 32.0 : 4.0;
                        final maxWidth = screenWidth > 800
                            ? 900.0
                            : double.infinity;
                        final dialogWidth = min(
                          screenWidth - margin,
                          maxWidth,
                        ).toDouble();
                        return SizedBox(
                          width: dialogWidth,
                          child: GoogleDriveBackupDialog(
                            disableAutoRestore: true,
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
                                    final imported =
                                        await chat_json_utils
                                            .ChatJsonUtils.importAllFromJson(
                                          jsonStr,
                                        );
                                    if (imported != null) {
                                      await captured.applyImportedChat(
                                        imported,
                                      );
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
                // If the dialog returned restored JSON (when no ChatProvider was passed), import it.
                if (res is Map && res['restoredJson'] is String && cp == null) {
                  final jsonStr = res['restoredJson'] as String;
                  try {
                    final imported =
                        await chat_json_utils.ChatJsonUtils.importAllFromJson(
                          jsonStr,
                          onError: (err) => op.setImportError(err),
                        );
                    if (imported != null) {
                      await op.applyImportedChat(imported);
                      if (widget.onImportJson != null) {
                        await widget.onImportJson!(imported);
                      }
                      if (mounted) setState(() {});
                    } else {
                      await showAppDialog(
                        builder: (ctx) => AlertDialog(
                          title: const Text('Error al importar'),
                          content: Text(op.importError ?? 'Error desconocido'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    await showAppDialog(
                      builder: (ctx) => AlertDialog(
                        title: const Text('Error'),
                        content: Text(e.toString()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                }
                return;
              }
              if (value == 'clear') {
                if (widget.onClearAllDebug != null) {
                  widget.onClearAllDebug!();
                } else {
                  setState(() {});
                }
                return;
              }
              if (value == 'import') {
                await _handleImportJson(provider);
                return;
              }
              if (value == 'restore_local') {
                await _handleRestoreFromLocal(provider);
                return;
              }
              if (value == 'backup_google') {
                final ChatProvider? cp = widget.chatProvider;
                final op = provider;
                final res2 = await showAppDialog<dynamic>(
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: Builder(
                      builder: (ctxInner) {
                        final screenWidth = MediaQuery.of(ctxInner).size.width;
                        final margin = screenWidth > 800 ? 32.0 : 4.0;
                        final maxWidth = screenWidth > 800
                            ? 900.0
                            : double.infinity;
                        final dialogWidth = min(
                          screenWidth - margin,
                          maxWidth,
                        ).toDouble();
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
                                    final imported =
                                        await chat_json_utils
                                            .ChatJsonUtils.importAllFromJson(
                                          jsonStr,
                                        );
                                    if (imported != null) {
                                      await captured.applyImportedChat(
                                        imported,
                                      );
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
                if (res2 is Map &&
                    res2['restoredJson'] is String &&
                    cp == null) {
                  final jsonStr = res2['restoredJson'] as String;
                  try {
                    final imported =
                        await chat_json_utils.ChatJsonUtils.importAllFromJson(
                          jsonStr,
                          onError: (err) => op.setImportError(err),
                        );
                    if (imported != null) {
                      await op.applyImportedChat(imported);
                      if (widget.onImportJson != null) {
                        await widget.onImportJson!(imported);
                      }
                      if (mounted) setState(() {});
                    } else {
                      await showAppDialog(
                        builder: (ctx) => AlertDialog(
                          title: const Text('Error al importar'),
                          content: Text(op.importError ?? 'Error desconocido'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    await showAppDialog(
                      builder: (ctx) => AlertDialog(
                        title: const Text('Error'),
                        content: Text(e.toString()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                }
                return;
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: provider.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1) País de usuario
              _sectionHeader('Mis datos', icon: Icons.person),
              CountryAutocomplete(
                selectedCountryCode: provider.userCountryCode,
                labelText: 'Tu país',
                prefixIcon: Icons.flag,
                validator: (_) => provider.userCountryCode?.isNotEmpty == true
                    ? null
                    : 'Obligatorio',
                helperText: provider.userCountryCode?.isNotEmpty == true
                    ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(provider.userCountryCode!)}'
                    : null,
                onCountrySelected: (code) {
                  provider.setUserCountryCode(code);
                },
              ),
              const SizedBox(height: 18),

              // 2) Nombre de usuario
              TextFormField(
                controller: _userNameController,
                onChanged: (value) {
                  provider.setUserName(value);
                },
                style: const TextStyle(
                  color: AppColors.primary,
                  fontFamily: 'FiraMono',
                ),
                decoration: const InputDecoration(
                  labelText: 'Tu nombre',
                  labelStyle: TextStyle(color: AppColors.secondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  prefixIcon: Icon(Icons.person, color: AppColors.secondary),
                  fillColor: Colors.black,
                  filled: true,
                ),
                validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 18),

              // 3) Fecha de nacimiento
              BirthDateField(
                controller: provider.birthDateController,
                userBirthday: provider.userBirthday,
                onBirthdayChanged: (d) => provider.setUserBirthday(d),
              ),
              const SizedBox(height: 18),

              // 4) País de la IA
              _sectionHeader('Datos de la AI-Chan', icon: Icons.smart_toy),
              CountryAutocomplete(
                key: ValueKey('ai-country-${provider.aiCountryCode ?? 'none'}'),
                selectedCountryCode: provider.aiCountryCode,
                labelText: 'País de la AI-Chan',
                prefixIcon: Icons.flag,
                validator: (_) => provider.aiCountryCode?.isNotEmpty == true
                    ? null
                    : 'Obligatorio',
                helperText: provider.aiCountryCode?.isNotEmpty == true
                    ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(provider.aiCountryCode!)}'
                    : null,
                // Lista de países preferidos (cultura otaku/friki, industria tech)
                preferredCountries: const [
                  'JP', // Japón
                  'KR', // Corea del Sur
                  'US', // Estados Unidos
                  'MX', // México
                  'BR', // Brasil
                  'CN', // China
                  'GB', // Reino Unido
                  'SE', // Suecia
                  'FI', // Finlandia
                  'PL', // Polonia
                  'DE', // Alemania
                  'NL', // Países Bajos
                  'CA', // Canadá
                  'AU', // Australia
                  'SG', // Singapur
                  'NO', // Noruega
                ],
                onCountrySelected: (code) {
                  provider.setAiCountryCode(code);
                },
              ),
              const SizedBox(height: 18),

              // 5) Nombre de la IA
              FemaleNameAutocomplete(
                key: ValueKey('ai-name-${provider.aiCountryCode ?? 'none'}'),
                selectedName: provider.aiNameController?.text,
                countryCode: provider.aiCountryCode,
                labelText: 'Nombre de la AI-Chan',
                prefixIcon: Icons.smart_toy,
                controller: provider.aiNameController,
                validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                onNameSelected: (name) {
                  provider.setAiName(name);
                },
                onChanged: (name) {
                  provider.setAiName(name);
                },
              ),
              const SizedBox(height: 18),

              // Historia de cómo se conocieron
              TextFormField(
                controller: provider.meetStoryController,
                onChanged: onMeetStoryChanged,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontFamily: 'FiraMono',
                ),
                decoration: const InputDecoration(
                  labelText: '¿Cómo os conocísteis?',
                  hintText: 'Escribe o pulsa sugerir',
                  labelStyle: TextStyle(color: AppColors.secondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  prefixIcon: Icon(Icons.favorite, color: AppColors.secondary),
                  fillColor: Colors.black,
                  filled: true,
                ),
                maxLines: 2,
                validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 8),
              CyberpunkButton(
                onPressed: provider.loadingStory
                    ? null
                    : () => provider.suggestStory(context),
                text: 'Sugerir historia',
                icon: provider.loadingStory
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: AppColors.secondary,
                          strokeWidth: 2,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 28),

              CyberpunkButton(
                onPressed: _formCompleto && !provider.loadingStory
                    ? () async {
                        // Clean Architecture: Use FormOnboardingController for form processing
                        final result = await _formController.processForm(
                          userName: provider.userNameController.text,
                          aiName: provider.aiNameController?.text ?? '',
                          birthDateText: provider.birthDateController.text,
                          meetStory: provider.meetStoryController.text,
                          userCountryCode: provider.userCountryCode,
                          aiCountryCode: provider.aiCountryCode,
                        );

                        if (result.success) {
                          await widget.onFinish(
                            userName: result.userName!,
                            aiName: result.aiName!,
                            userBirthday: result.userBirthday!,
                            meetStory: result.meetStory!,
                            userCountryCode: result.userCountryCode,
                            aiCountryCode: result.aiCountryCode,
                            appearance: null,
                          );
                        } else {
                          await showAppDialog(
                            builder: (ctx) => AlertDialog(
                              title: const Text('Error en el formulario'),
                              content: Text(result.errorMessage),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        }
                      }
                    : null,
                text: 'コンティニュー',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Eliminado _CountryAutocomplete en favor del mismo patrón de Autocomplete<String> que el nombre de AI-Chan
