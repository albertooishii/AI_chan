import 'package:ai_chan/call/domain/domain.dart';

/// Caso de uso para iniciar una nueva llamada de voz
class StartCallUseCase {
  const StartCallUseCase(this._repository, this._realtimeClient);
  final ICallRepository _repository;
  final IRealtimeCallClient _realtimeClient;

  /// Inicia una nueva llamada de voz
  Future<Call> execute({
    required final CallProvider provider,
    required final String model,
    required final String voice,
    final String languageCode = 'es-ES',
    final CallConfig? config,
    final Map<String, dynamic>? metadata,
  }) async {
    // Validar configuración
    final effectiveConfig = config ?? CallConfig.defaultConfig();
    if (!CallValidationService.isCallConfigValid(effectiveConfig)) {
      throw ArgumentError('Invalid call configuration');
    }

    // Verificar compatibilidad del proveedor
    if (!CallValidationService.isProviderCompatible(
      provider,
      requiresRealtime: provider.supportsRealtime,
    )) {
      throw ArgumentError(
        'Provider $provider is not compatible with current requirements',
      );
    }

    // Crear nueva llamada
    final call = CallOrchestrationService.createCall(
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
