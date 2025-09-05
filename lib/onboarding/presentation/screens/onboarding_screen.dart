import 'package:ai_chan/core/presentation/widgets/cyberpunk_button.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import '../widgets/birth_date_field.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/widgets/country_autocomplete.dart';
import 'package:ai_chan/shared/widgets/female_name_autocomplete.dart';
import 'package:ai_chan/onboarding/application/controllers/form_onboarding_controller.dart';
import 'conversational_onboarding_screen.dart';
import 'package:ai_chan/chat/application/adapters/chat_provider_adapter.dart'; // ✅ DDD: Para type safety en ETAPA 2

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
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;
  // Optional external provider instance (presentation widgets should avoid creating providers internally when possible)
  final OnboardingProvider? onboardingProvider;
  // Optional ChatProvider instance so presentation widgets receive it via constructor
  // instead of depending on provider package APIs internally.
  final ChatProviderAdapter? chatProvider; // ✅ DDD: Type safety en ETAPA 2

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
  final ChatProviderAdapter? chatProvider; // ✅ DDD: Type safety en ETAPA 2
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

  bool get _formCompleto {
    final provider = widget.onboardingProvider;
    return provider.userNameController.text.trim().isNotEmpty &&
        (provider.aiNameController?.text.trim().isNotEmpty ?? false) &&
        provider.userBirthdate != null &&
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
                userBirthdate: provider.userBirthdate,
                onBirthdateChanged: (d) => provider.setUserBirthdate(d),
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
                            userBirthdate: result.userBirthdate!,
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
