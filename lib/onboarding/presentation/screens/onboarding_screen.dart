import 'package:ai_chan/core/presentation/widgets/cyberpunk_button.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import '../widgets/birth_date_field.dart';
import 'package:ai_chan/onboarding/application/controllers/onboarding_lifecycle_controller.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/widgets/country_autocomplete.dart';
import 'package:ai_chan/shared/widgets/female_name_autocomplete.dart';
import 'package:ai_chan/onboarding/application/controllers/form_onboarding_controller.dart';
import 'conversational_onboarding_screen.dart';
import 'onboarding_mode_selector.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart'; // ✅ DDD: ETAPA 3 - ChatApplicationService directo
import 'package:ai_chan/core/di.dart' as di;

/// Callback typedef para finalizar el onboarding
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

class OnboardingScreen extends StatefulWidget {
  // ✅ DDD: ETAPA 3 - Migrado a ChatApplicationService

  const OnboardingScreen({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
    this.onboardingLifecycle,
    this.chatProvider,
  });
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(ChatExport importedChat)? onImportJson;
  // Optional external provider instance (presentation widgets should avoid creating providers internally when possible)
  final OnboardingLifecycleController? onboardingLifecycle;
  // Optional ChatProvider instance so presentation widgets receive it via constructor
  // instead of depending on provider package APIs internally.
  final ChatApplicationService? chatProvider;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  OnboardingLifecycleController? _createdLifecycle;

  @override
  void initState() {
    super.initState();
    // If no external provider was supplied, create one and retain it across rebuilds.
    if (widget.onboardingLifecycle == null) {
      _createdLifecycle = OnboardingLifecycleController(
        chatRepository: di.getChatRepository(),
      );
    }
  }

  @override
  void dispose() {
    try {
      // Only dispose if we created it here.
      _createdLifecycle?.dispose();
    } on Exception catch (_) {}
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final effectiveLifecycle = widget.onboardingLifecycle ?? _createdLifecycle!;
    // The onboarding lifecycle controller is passed explicitly to the presentation
    // content. Presentation widgets must not call provider package APIs directly.
    return _OnboardingScreenContent(
      onboardingLifecycle: effectiveLifecycle,
      chatProvider: widget.chatProvider,
      onFinish: widget.onFinish,
      onClearAllDebug: widget.onClearAllDebug,
      onImportJson: widget.onImportJson,
    );
  }
}

class _OnboardingScreenContent extends StatefulWidget {
  const _OnboardingScreenContent({
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
    required this.onboardingLifecycle,
    this.chatProvider,
  });
  // does not call provider package APIs internally.
  final OnboardingLifecycleController onboardingLifecycle;
  // Optional chat provider instance passed from the parent to avoid Provider.of inside presentation.
  final ChatApplicationService?
  chatProvider; // ✅ DDD: ETAPA 3 - Migrado a ChatApplicationService
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(ChatExport importedChat)? onImportJson;

  @override
  State<_OnboardingScreenContent> createState() =>
      _OnboardingScreenContentState();
}

class _OnboardingScreenContentState extends State<_OnboardingScreenContent> {
  // Clean Architecture: Controller para manejar lógica de negocio
  late final FormOnboardingController _formController;

  // Persisted Google account fallback (removed: menu now shows a static entry)

  // Subtítulo con divisor para secciones (estilo sutil)
  Widget _sectionHeader(final String title, {final IconData? icon}) {
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

  // _formCompleto replaced by _formController.isFormCompleteComputed

  late final TextEditingController _userNameController;

  @override
  void initState() {
    super.initState();
    // Clean Architecture: Initialize controller
    _formController = FormOnboardingController();
    _userNameController = TextEditingController(
      text: _formController.userNameController.text,
    );
    // Register listeners: provider for onboarding lifecycle and controller for form state
    widget.onboardingLifecycle.addListener(_onProviderChanged);
    _formController.addListener(_onProviderChanged);
    // No preload persisted Google account info: menu shows a static label now.
  }

  @override
  void dispose() {
    widget.onboardingLifecycle.removeListener(_onProviderChanged);
    _formController.removeListener(_onProviderChanged);
    _userNameController.dispose();
    _formController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(final BuildContext context) {
    void onMeetStoryChanged(final String value) {
      _formController.setMeetStory(value);
      setState(() {}); // Fuerza refresco para reactivar el botón
    }

    return Scaffold(
      appBar: AppBar(
        // Mostrar siempre un botón explícito de 'atrás' que lleve al selector
        // de modo de onboarding. Usamos pushReplacement para garantizar que
        // no existan múltiples rutas de onboarding en la pila.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => OnboardingModeSelector(
                  onFinish: widget.onFinish,
                  onClearAllDebug: widget.onClearAllDebug,
                  onImportJson: widget.onImportJson,
                  onboardingLifecycle: widget.onboardingLifecycle,
                  chatProvider: widget.chatProvider,
                ),
              ),
            );
          },
        ),
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
                    onboardingLifecycle: widget.onboardingLifecycle,
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formController.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1) País de usuario
              _sectionHeader('Mis datos', icon: Icons.person),
              CountryAutocomplete(
                selectedCountryCode: _formController.userCountryCode,
                labelText: 'Tu país',
                prefixIcon: Icons.flag,
                validator: (_) =>
                    _formController.userCountryCode?.isNotEmpty == true
                    ? null
                    : 'Obligatorio',
                helperText: _formController.userCountryCode?.isNotEmpty == true
                    ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(_formController.userCountryCode!)}'
                    : null,
                onCountrySelected: (final code) {
                  _formController.setUserCountryCode(code);
                },
              ),
              const SizedBox(height: 18),

              // 2) Nombre de usuario
              TextFormField(
                controller: _userNameController,
                onChanged: (final value) {
                  _formController.setUserName(value);
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
                validator: (final v) =>
                    v == null || v.isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 18),

              // 3) Fecha de nacimiento
              BirthDateField(
                controller: _formController.birthDateController,
                userBirthdate: _formController.userBirthdate,
                onBirthdateChanged: (final d) =>
                    _formController.setUserBirthdate(d),
              ),
              const SizedBox(height: 18),

              // 4) País de la IA
              _sectionHeader('Datos de la AI-Chan', icon: Icons.smart_toy),
              CountryAutocomplete(
                key: ValueKey(
                  'ai-country-${_formController.aiCountryCode ?? 'none'}',
                ),
                selectedCountryCode: _formController.aiCountryCode,
                labelText: 'País de la AI-Chan',
                prefixIcon: Icons.flag,
                validator: (_) =>
                    _formController.aiCountryCode?.isNotEmpty == true
                    ? null
                    : 'Obligatorio',
                helperText: _formController.aiCountryCode?.isNotEmpty == true
                    ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(_formController.aiCountryCode!)}'
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
                onCountrySelected: (final code) {
                  _formController.setAiCountryCode(code);
                },
              ),
              const SizedBox(height: 18),

              // 5) Nombre de la IA
              FemaleNameAutocomplete(
                key: ValueKey(
                  'ai-name-${_formController.aiCountryCode ?? 'none'}',
                ),
                selectedName: _formController.aiNameController.text,
                countryCode: _formController.aiCountryCode,
                labelText: 'Nombre de la AI-Chan',
                prefixIcon: Icons.smart_toy,
                controller: _formController.aiNameController,
                validator: (final v) =>
                    v == null || v.isEmpty ? 'Obligatorio' : null,
                onNameSelected: (final name) {
                  _formController.setAiName(name);
                },
                onChanged: (final name) {
                  _formController.setAiName(name);
                },
              ),
              const SizedBox(height: 18),

              // Historia de cómo se conocieron
              TextFormField(
                controller: _formController.meetStoryController,
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
                validator: (final v) =>
                    v == null || v.isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 8),
              CyberpunkButton(
                onPressed: _formController.isLoading
                    ? null
                    : () => _formController.suggestStory(context),
                text: 'Sugerir historia',
                icon: _formController.isLoading
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
                onPressed:
                    _formController.isFormCompleteComputed &&
                        !_formController.isLoading
                    ? () async {
                        // Clean Architecture: Use FormOnboardingController for form processing
                        final result = await _formController.processForm(
                          userName: _formController.userNameController.text,
                          aiName: _formController.aiNameController.text,
                          birthDateText:
                              _formController.birthDateController.text,
                          meetStory: _formController.meetStoryController.text,
                          userCountryCode: _formController.userCountryCode,
                          aiCountryCode: _formController.aiCountryCode,
                        );

                        if (result.success) {
                          await widget.onFinish(
                            userName: result.userName!,
                            aiName: result.aiName!,
                            userBirthdate: result.userBirthdate!,
                            meetStory: result.meetStory!,
                            userCountryCode: result.userCountryCode,
                            aiCountryCode: result.aiCountryCode,
                            appearance: null,
                          );
                        } else {
                          await showAppDialog(
                            builder: (final ctx) => AlertDialog(
                              title: const Text('Error en el formulario'),
                              content: Text(
                                result.errorMessage ?? 'Error desconocido',
                              ),
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
