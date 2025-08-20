import 'package:ai_chan/core/presentation/widgets/cyberpunk_button.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/constants/app_colors.dart';
import 'package:ai_chan/utils/chat_json_utils.dart' as chat_json_utils;
import '../widgets/birth_date_field.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:provider/provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/utils/locale_utils.dart';
import 'package:ai_chan/constants/countries_es.dart';
import 'package:ai_chan/constants/female_names.dart';

class OnboardingScreen extends StatelessWidget {
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

  const OnboardingScreen({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OnboardingProvider(),
      child: _OnboardingScreenContent(
        onFinish: onFinish,
        onClearAllDebug: onClearAllDebug,
        onImportJson: onImportJson,
      ),
    );
  }
}

class _OnboardingScreenContent extends StatefulWidget {
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
  });

  @override
  State<_OnboardingScreenContent> createState() =>
      _OnboardingScreenContentState();
}

class _OnboardingScreenContentState extends State<_OnboardingScreenContent> {
  // Helper: normaliza strings para búsquedas sin acentos
  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');

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
      await showDialog(
        context: context,
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
        await showDialog(
          context: context,
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

  bool get _formCompleto {
    final provider = Provider.of<OnboardingProvider>(context, listen: false);
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
      text: Provider.of<OnboardingProvider>(
        context,
        listen: false,
      ).userNameController.text,
    );
  }

  @override
  void dispose() {
    _userNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<OnboardingProvider>(context);
    void onMeetStoryChanged(String value) {
      provider.setMeetStory(value);
      setState(() {}); // Fuerza refresco para reactivar el botón
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text.rich(
          TextSpan(
            text: 'AI-チャン',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              fontFamily: 'FiraMono',
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'import',
                child: Text(
                  'Importar chat',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
              PopupMenuItem<String>(
                value: 'clear',
                child: Text(
                  'Borrar todo (debug)',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ),
            ],
            onSelected: (value) async {
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
                  final items = CountriesEs.items;
                  final q = _normalize(textEditingValue.text.trim());
                  final opts = items.map((c) {
                    final flag = LocaleUtils.flagEmojiForCountry(c.iso2);
                    return '${flag.isNotEmpty ? '$flag ' : ''}${c.nameEs} (${c.iso2})';
                  });
                  if (q.isEmpty) return opts.take(50);
                  return opts.where((o) => _normalize(o).contains(q)).take(50);
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
              const BirthDateField(),
              const SizedBox(height: 18),

              // 4) País de la IA
              _sectionHeader('Datos de la AI-Chan', icon: Icons.smart_toy),
              Autocomplete<String>(
                key: ValueKey('ai-country-${provider.aiCountryCode ?? 'none'}'),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final items = CountriesEs.items;
                  final q = _normalize(textEditingValue.text.trim());
                  final opts = items.map((c) {
                    final flag = LocaleUtils.flagEmojiForCountry(c.iso2);
                    return '${flag.isNotEmpty ? '$flag ' : ''}${c.nameEs} (${c.iso2})';
                  });
                  if (q.isEmpty) return opts.take(50);
                  return opts.where((o) => _normalize(o).contains(q)).take(50);
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
