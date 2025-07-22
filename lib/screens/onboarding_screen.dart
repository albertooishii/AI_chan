import 'package:ai_chan/widgets/cyberpunk_button.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/chat_json_utils.dart' as chat_json_utils;
import '../widgets/birth_date_field.dart';
import '../providers/onboarding_provider.dart';
import 'package:provider/provider.dart';

import '../models/imported_chat.dart';

class OnboardingScreen extends StatelessWidget {
  final Future<void> Function({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
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
  Future<void> _handleImportJson(OnboardingProvider provider) async {
    final option = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Importar chat',
          style: TextStyle(color: Colors.pinkAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text(
                'Pegar JSON',
                style: TextStyle(color: Colors.black87),
              ),
              onPressed: () => Navigator.of(ctx).pop('paste'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text(
                'Seleccionar archivo',
                style: TextStyle(color: Colors.black87),
              ),
              onPressed: () => Navigator.of(ctx).pop('file'),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.primary),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
    if (!mounted) return;
    String? jsonStr;
    String? error;
    if (option == 'paste') {
      jsonStr = await chat_json_utils.ChatJsonUtils.pasteJsonDialog(context);
    } else if (option == 'file') {
      final result = await chat_json_utils.ChatJsonUtils.pickJsonFile();
      jsonStr = result.$1;
      error = result.$2;
    }
    if (!mounted) return;
    if (error != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al leer archivo'),
          content: Text(error!),
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
      final imported = chat_json_utils.ChatJsonUtils.importAllFromJson(
        jsonStr,
        onError: (err) => importError = err,
      );
      if (importError != null || imported == null) {
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
        provider.meetStoryController.text.trim().isNotEmpty;
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
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  return provider.aiNameSuggestions.where(
                    (option) => option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
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
              const BirthDateField(),
              const SizedBox(height: 18),
              TextFormField(
                controller: provider.meetStoryController,
                onChanged: onMeetStoryChanged,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontFamily: 'FiraMono',
                ),
                decoration: InputDecoration(
                  labelText: "¿Cómo se conocieron?",
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
