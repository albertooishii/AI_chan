import 'package:ai_chan/voice/domain/domain.dart';

/// Caso de uso para iniciar una nueva llamada de voz
class StartVoiceCallUseCase {
  final IVoiceCallRepository _repository;
  final IRealtimeVoiceClient _realtimeClient;

  const StartVoiceCallUseCase(this._repository, this._realtimeClient);

  /// Inicia una nueva llamada de voz
  Future<VoiceCall> execute({
    required VoiceProvider provider,
    required String model,
    required String voice,
    String languageCode = 'es-ES',
    CallConfig? config,
    Map<String, dynamic>? metadata,
  }) async {
    // Validar configuración
    final effectiveConfig = config ?? CallConfig.defaultConfig();
    if (!VoiceCallValidationService.isCallConfigValid(effectiveConfig)) {
      throw ArgumentError('Invalid call configuration');
    }

    // Verificar compatibilidad del proveedor
    if (!VoiceCallValidationService.isProviderCompatible(
      provider,
      requiresRealtime: provider.supportsRealtime,
    )) {
      throw ArgumentError(
        'Provider $provider is not compatible with current requirements',
      );
    }

    // Crear nueva llamada
    final call = VoiceCallOrchestrationService.createCall(
      id: _generateCallId(),
      provider: provider,
      model: model,
      voice: voice,
      languageCode: languageCode,
      config: effectiveConfig,
      metadata: metadata,
    );

    // Guardar llamada en repositorio
    await _repository.saveCall(call);

    // Conectar cliente realtime
    await _realtimeClient.connect(
      systemPrompt: effectiveConfig.systemPrompt,
      voice: voice,
      options: {
        'temperature': effectiveConfig.temperature,
        'maxTokens': effectiveConfig.maxTokens,
        'turnDetectionType': effectiveConfig.turnDetectionType,
        ...?effectiveConfig.additionalOptions,
      },
    );

    return call;
  }

  /// Genera un ID único para la llamada
  String _generateCallId() {
    return 'call_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }
}
