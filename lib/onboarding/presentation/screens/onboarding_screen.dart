import 'package:ai_chan/core/presentation/widgets/cyberpunk_button.dart';
// onboarding_provider imported once below; avoid duplicate import
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/shared/constants/countries_es.dart';
import 'package:ai_chan/shared/constants/female_names.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import '../widgets/birth_date_field.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
// import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/utils/string_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:math';
// archive and convert handled by BackupService
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/shared/widgets/google_drive_backup_dialog.dart';

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
    Map<String, dynamic>? appearance,
  })
  onFinish;
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
  final Future<void> Function({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
    Map<String, dynamic>? appearance,
  })
  onFinish;
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
  // Persisted Google account fallback (removed: menu now shows a static entry)

  // Helper: auto-abrir el Autocomplete al enfocar
  void _attachAutoOpen(TextEditingController controller, FocusNode focusNode) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        final original = controller.text;
        controller.text = ' ';
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        Future.microtask(() {
          controller.text = original;
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        });
      }
    });
  }

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

  Future<void> _handleImportJson(OnboardingProvider provider) async {
    final result = await chat_json_utils.ChatJsonUtils.importJsonFile();
    if (!mounted) return;
    String? jsonStr = result.$1;
    String? error = result.$2;
    if (!mounted) return;
    if (error != null) {
      await showAppDialog(
        builder: (ctx) => AlertDialog(
          title: const Text('Error al leer archivo'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (jsonStr != null &&
        jsonStr.trim().isNotEmpty &&
        widget.onImportJson != null) {
      String? importError;
      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (err) => importError = err,
      );
      if (importError != null || imported == null) {
        if (!mounted) return;
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            title: const Text('Error al importar'),
            content: Text(
              'No se pudo importar la biografía: campo problemático: ${importError ?? 'Error desconocido'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      await widget.onImportJson!(imported);
    }
  }

  Future<void> _handleRestoreFromLocal(OnboardingProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      final f = File(path);

      // Usar BackupService para extraer JSON y restaurar imágenes/audio en sus carpetas
      final jsonStr = await BackupService.extractJsonAndRestoreMedia(f);

      if (jsonStr.trim().isEmpty) {
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Archivo vacío o no contiene JSON'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (err) => provider.setImportError(err),
      );
      if (imported == null) {
        await showAppDialog(
          builder: (ctx) => AlertDialog(
            title: const Text('Error al importar'),
            content: Text(provider.importError ?? 'Error desconocido'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (widget.onImportJson != null) {
        await widget.onImportJson!(imported);
        return;
      }

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
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              items.add(
                PopupMenuItem<String>(
                  value: 'restore_local',
                  child: Row(
                    children: [
                      Icon(Icons.file_upload, color: AppColors.primary),
                      const SizedBox(width: 8),
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
                PopupMenuItem<String>(
                  value: 'backup_status',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_to_drive,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
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
                            clientId: 'YOUR_GOOGLE_CLIENT_ID',
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
                                  }) async {
                                    final captured = cp;
                                    await captured.updateGoogleAccountInfo(
                                      email: email,
                                      avatarUrl: avatarUrl,
                                      name: name,
                                      linked: linked,
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
                            clientId: 'YOUR_GOOGLE_CLIENT_ID',
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
                                  }) async {
                                    final captured = cp;
                                    await captured.updateGoogleAccountInfo(
                                      email: email,
                                      avatarUrl: avatarUrl,
                                      name: name,
                                      linked: linked,
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
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final items = List<CountryItem>.from(CountriesEs.items);
                  final q = StringUtils.normalizeForSearch(
                    textEditingValue.text.trim(),
                  );
                  final opts = items.map((c) {
                    final flag = LocaleUtils.flagEmojiForCountry(c.iso2);
                    return '${flag.isNotEmpty ? '$flag ' : ''}${c.nameEs} (${c.iso2})';
                  });
                  if (q.isEmpty) return opts.take(50);
                  return opts
                      .where(
                        (o) => StringUtils.normalizeForSearch(o).contains(q),
                      )
                      .take(50);
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  // Inicializa el texto si ya hay código guardado
                  final code = provider.userCountryCode;
                  if ((controller.text.isEmpty) &&
                      code != null &&
                      code.isNotEmpty) {
                    final name = CountriesEs.codeToName[code.toUpperCase()];
                    if (name != null) {
                      final flag = LocaleUtils.flagEmojiForCountry(code);
                      controller.text =
                          '${flag.isNotEmpty ? '$flag ' : ''}$name ($code)';
                    }
                  }
                  // Abrir opciones al enfocar (inserta un espacio temporal y lo revierte)
                  _attachAutoOpen(controller, focusNode);
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontFamily: 'FiraMono',
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tu país',
                      labelStyle: const TextStyle(color: AppColors.secondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.secondary),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.flag,
                        color: AppColors.secondary,
                      ),
                      helperText: provider.userCountryCode?.isNotEmpty == true
                          ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(provider.userCountryCode!)}'
                          : null,
                      helperStyle: const TextStyle(color: AppColors.secondary),
                      fillColor: Colors.black,
                      filled: true,
                    ),
                    validator: (_) =>
                        provider.userCountryCode?.isNotEmpty == true
                        ? null
                        : 'Obligatorio',
                    onEditingComplete: onEditingComplete,
                  );
                },
                onSelected: (selection) {
                  // Extrae ISO2 del texto "Nombre (XX)"
                  final match = RegExp(r'\(([^)]+)\)$').firstMatch(selection);
                  final code = match != null ? match.group(1)! : '';
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
                decoration: InputDecoration(
                  labelText: "Tu nombre",
                  labelStyle: const TextStyle(color: AppColors.secondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  prefixIcon: const Icon(
                    Icons.person,
                    color: AppColors.secondary,
                  ),
                  fillColor: Colors.black,
                  filled: true,
                ),
                validator: (v) => v == null || v.isEmpty ? "Obligatorio" : null,
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
              Autocomplete<String>(
                key: ValueKey('ai-country-${provider.aiCountryCode ?? 'none'}'),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final items = List<CountryItem>.from(CountriesEs.items);
                  // Poner una lista de países preferidos al inicio en el orden deseado.
                  // Orden elegido (prioridad por cultura "friki", industria y hubs regionales):
                  // Japón, Corea del Sur, Estados Unidos, México, Brasil, China,
                  // Reino Unido, Suecia, Finlandia, Polonia, Alemania, Países Bajos,
                  // Canadá, Australia, Singapur, Noruega
                  const preferredIsoOrder = [
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
                  ];
                  for (var i = preferredIsoOrder.length - 1; i >= 0; i--) {
                    final iso = preferredIsoOrder[i];
                    final idx = items.indexWhere((c) => c.iso2 == iso);
                    if (idx != -1) {
                      final it = items.removeAt(idx);
                      items.insert(0, it);
                    }
                  }
                  final q = StringUtils.normalizeForSearch(
                    textEditingValue.text.trim(),
                  );
                  final opts = items.map((c) {
                    final flag = LocaleUtils.flagEmojiForCountry(c.iso2);
                    return '${flag.isNotEmpty ? '$flag ' : ''}${c.nameEs} (${c.iso2})';
                  });
                  if (q.isEmpty) return opts.take(50);
                  return opts
                      .where(
                        (o) => StringUtils.normalizeForSearch(o).contains(q),
                      )
                      .take(50);
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  // Inicializa el texto si ya hay código guardado
                  final code = provider.aiCountryCode;
                  if ((controller.text.isEmpty) &&
                      code != null &&
                      code.isNotEmpty) {
                    final name = CountriesEs.codeToName[code.toUpperCase()];
                    if (name != null) {
                      final flag = LocaleUtils.flagEmojiForCountry(code);
                      controller.text =
                          '${flag.isNotEmpty ? '$flag ' : ''}$name ($code)';
                    }
                  }
                  // Abrir opciones al enfocar (inserta un espacio temporal y lo revierte)
                  _attachAutoOpen(controller, focusNode);
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontFamily: 'FiraMono',
                    ),
                    decoration: InputDecoration(
                      labelText: 'País de la AI-Chan',
                      labelStyle: const TextStyle(color: AppColors.secondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.secondary),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.flag,
                        color: AppColors.secondary,
                      ),
                      helperText: provider.aiCountryCode?.isNotEmpty == true
                          ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(provider.aiCountryCode!)}'
                          : null,
                      helperStyle: const TextStyle(color: AppColors.secondary),
                      fillColor: Colors.black,
                      filled: true,
                    ),
                    validator: (_) => provider.aiCountryCode?.isNotEmpty == true
                        ? null
                        : 'Obligatorio',
                    onEditingComplete: onEditingComplete,
                  );
                },
                onSelected: (selection) {
                  final match = RegExp(r'\(([^)]+)\)$').firstMatch(selection);
                  final code = match != null ? match.group(1)! : '';
                  provider.setAiCountryCode(code);
                },
              ),
              const SizedBox(height: 18),

              // 5) Nombre de la IA
              Autocomplete<String>(
                key: ValueKey('ai-name-${provider.aiCountryCode ?? 'none'}'),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    // Sugerencias base por país de la IA si no hay texto
                    final base = FemaleNamesRepo.forCountry(
                      provider.aiCountryCode,
                    );
                    return base.take(20);
                  }
                  final source = FemaleNamesRepo.forCountry(
                    provider.aiCountryCode,
                  );
                  return source
                      .where(
                        (option) => option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ),
                      )
                      .take(50);
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                      // Enlaza el controller al provider para que nunca sea null
                      provider.setAiNameController(controller);
                      // Sincroniza el valor inicial solo si está vacío
                      if (controller.text.isEmpty &&
                          (provider.aiNameController?.text.isNotEmpty ??
                              false)) {
                        controller.text = provider.aiNameController!.text;
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (value) {
                          provider.setAiName(value);
                        },
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontFamily: 'FiraMono',
                        ),
                        decoration: InputDecoration(
                          labelText: "Nombre de la AI-Chan",
                          labelStyle: const TextStyle(
                            color: AppColors.secondary,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.secondary),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          prefixIcon: const Icon(
                            Icons.smart_toy,
                            color: AppColors.secondary,
                          ),
                          fillColor: Colors.black,
                          filled: true,
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? "Obligatorio" : null,
                        onEditingComplete: onEditingComplete,
                      );
                    },
                onSelected: (selection) {
                  provider.setAiName(selection);
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
                decoration: InputDecoration(
                  labelText: "¿Cómo os conocísteis?",
                  hintText: "Escribe o pulsa sugerir",
                  labelStyle: const TextStyle(color: AppColors.secondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.secondary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  prefixIcon: const Icon(
                    Icons.favorite,
                    color: AppColors.secondary,
                  ),
                  fillColor: Colors.black,
                  filled: true,
                ),
                maxLines: 2,
                validator: (v) => v == null || v.isEmpty ? "Obligatorio" : null,
              ),
              const SizedBox(height: 8),
              CyberpunkButton(
                onPressed: provider.loadingStory
                    ? null
                    : () => provider.suggestStory(context),
                text: "Sugerir historia",
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
                        // Forzar sincronización de todos los valores del formulario
                        provider.setUserName(provider.userNameController.text);
                        provider.setAiName(
                          provider.aiNameController?.text ?? '',
                        );
                        provider.setMeetStory(
                          provider.meetStoryController.text,
                        );
                        final birthText = provider.birthDateController.text;
                        if (birthText.isNotEmpty) {
                          final parts = birthText.split('/');
                          if (parts.length == 3) {
                            final parsed = DateTime(
                              int.parse(parts[2]),
                              int.parse(parts[1]),
                              int.parse(parts[0]),
                            );
                            provider.setUserBirthday(parsed);
                          }
                        }

                        await widget.onFinish(
                          userName: provider.userNameController.text,
                          aiName: provider.aiNameController?.text ?? '',
                          userBirthday: provider.userBirthday!,
                          meetStory: provider.meetStoryController.text,
                          userCountryCode: provider.userCountryCode,
                          aiCountryCode: provider.aiCountryCode,
                          appearance: null,
                        );
                      }
                    : null,
                text: "コンティニュー",
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Eliminado _CountryAutocomplete en favor del mismo patrón de Autocomplete<String> que el nombre de AI-Chan
