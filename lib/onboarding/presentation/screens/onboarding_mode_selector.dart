import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'conversational_onboarding_screen.dart';
import 'onboarding_screen.dart';

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

/// Pantalla de selección de modo de onboarding con conversacional por defecto
class OnboardingModeSelector extends StatelessWidget {
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final Future<void> Function(dynamic importedChat)? onImportJson;
  final dynamic onboardingProvider;
  final dynamic chatProvider;

  const OnboardingModeSelector({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onImportJson,
    this.onboardingProvider,
    this.chatProvider,
  });

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
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_upload, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      'Importar datos',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              // TODO: Implementar acciones del menú
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
                                'assets/icon/app_icon.png',
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
                                                  onFinish: onFinish,
                                                  onboardingProvider:
                                                      onboardingProvider,
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
                                          onFinish: onFinish,
                                          onClearAllDebug: onClearAllDebug,
                                          onImportJson: onImportJson,
                                          onboardingProvider:
                                              onboardingProvider,
                                          chatProvider: chatProvider,
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
}
