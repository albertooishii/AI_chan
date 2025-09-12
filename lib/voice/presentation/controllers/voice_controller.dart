import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../application/services/voice_application_service.dart';
import '../../domain/entities/voice_session.dart';
import '../../../shared/ai_providers/core/models/audio/voice_settings.dart';
import '../../domain/interfaces/voice_services.dart';

/// 🎯 DDD: Controlador de voz para Flutter
/// Maneja la presentación y el estado de la UI
class VoiceController extends ChangeNotifier {
  VoiceController(final VoiceApplicationService appService)
    : _appService = appService;

  final VoiceApplicationService _appService;

  // Estado del controlador
  VoiceSessionState? _currentSessionState;
  VoiceCapabilities? _capabilities;
  bool _isLoading = false;
  String? _error;

  // Streams para eventos en tiempo real
  final StreamController<VoiceInteractionResult> _interactionController =
      StreamController.broadcast();
  final StreamController<VoiceResponseResult> _responseController =
      StreamController.broadcast();

  // Getters públicos
  VoiceSessionState? get currentSessionState => _currentSessionState;
  VoiceSession? get currentSession => _currentSessionState?.session;
  VoiceCapabilities? get capabilities => _capabilities;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasActiveSession => _currentSessionState?.isActive == true;

  // Streams públicos
  Stream<VoiceInteractionResult> get onInteraction =>
      _interactionController.stream;
  Stream<VoiceResponseResult> get onResponse => _responseController.stream;

  /// 🚀 Inicializar controlador
  Future<void> initialize() async {
    await _setLoading(true);
    try {
      _capabilities = await _appService.getVoiceCapabilities();
      _error = null;
    } on Exception catch (e) {
      _error = 'Error inicializando controlador: $e';
    } finally {
      await _setLoading(false);
    }
  }

  /// 🎙️ Iniciar nueva sesión de voz
  Future<void> startVoiceSession({
    final VoiceSettings? settings,
    final Map<String, dynamic>? metadata,
  }) async {
    await _setLoading(true);
    try {
      final sessionState = await _appService.startVoiceSession(
        settings: settings,
        metadata: metadata,
      );

      if (sessionState.hasError) {
        _error = sessionState.error;
      } else {
        _currentSessionState = sessionState;
        _error = null;
      }
    } on Exception catch (e) {
      _error = 'Error iniciando sesión: $e';
    } finally {
      await _setLoading(false);
    }
  }

  /// 💬 Procesar entrada del usuario
  Future<void> processUserInput({
    final String? text,
    final List<int>? audioData,
  }) async {
    if (!hasActiveSession) {
      _error = 'No hay sesión activa';
      notifyListeners();
      return;
    }

    await _setLoading(true);
    try {
      final result = await _appService.processUserInput(
        sessionId: currentSession!.id,
        text: text,
        audioData: audioData,
      );

      if (result.hasError) {
        _error = result.error;
      } else {
        // Actualizar estado de sesión
        _currentSessionState = VoiceSessionState(
          session: result.session!,
          isActive: true,
          stats: result.stats,
        );
        _error = null;

        // Emitir evento
        _interactionController.add(result);
      }
    } on Exception catch (e) {
      _error = 'Error procesando entrada: $e';
    } finally {
      await _setLoading(false);
    }
  }

  /// 🔊 Generar respuesta de voz
  Future<void> generateVoiceResponse(final String responseText) async {
    if (!hasActiveSession) {
      _error = 'No hay sesión activa';
      notifyListeners();
      return;
    }

    await _setLoading(true);
    try {
      final result = await _appService.generateVoiceResponse(
        sessionId: currentSession!.id,
        responseText: responseText,
      );

      if (result.hasError) {
        _error = result.error;
      } else {
        _error = null;
        // Emitir evento
        _responseController.add(result);
      }
    } on Exception catch (e) {
      _error = 'Error generando respuesta: $e';
    } finally {
      await _setLoading(false);
    }
  }

  /// ⚙️ Configurar voz
  Future<void> configureVoice(final VoiceSettings newSettings) async {
    if (!hasActiveSession) {
      _error = 'No hay sesión activa';
      notifyListeners();
      return;
    }

    await _setLoading(true);
    try {
      final result = await _appService.configureVoice(
        sessionId: currentSession!.id,
        newSettings: newSettings,
      );

      if (result.hasError) {
        _error = result.error;
      } else {
        // Actualizar estado
        _currentSessionState = VoiceSessionState(
          session: result.session!,
          isActive: true,
          validation: result.validation,
        );
        _error = null;
      }
    } on Exception catch (e) {
      _error = 'Error configurando voz: $e';
    } finally {
      await _setLoading(false);
    }
  }

  /// 🏁 Finalizar sesión
  void endVoiceSession() {
    if (!hasActiveSession) return;

    try {
      final sessionState = _appService.endVoiceSession(currentSession!.id);
      if (sessionState.hasError) {
        _error = sessionState.error;
      } else {
        _currentSessionState = sessionState;
        _error = null;
      }
    } on Exception catch (e) {
      _error = 'Error finalizando sesión: $e';
    }
    notifyListeners();
  }

  /// 🔍 Obtener voces disponibles
  Future<List<VoiceInfo>> getAvailableVoices({
    final String language = 'es-ES',
  }) async {
    try {
      final capabilities = await _appService.getVoiceCapabilities(
        language: language,
      );
      return capabilities.availableVoices;
    } on Exception {
      return [];
    }
  }

  /// 🎛️ Previsualizar voz
  Future<void> previewVoice({
    required final String voiceId,
    required final String language,
    final String? sampleText,
  }) async {
    await _setLoading(true);
    try {
      // TODO: Implementar preview cuando esté disponible
      await Future.delayed(const Duration(milliseconds: 500));
      _error = null;
    } on Exception catch (e) {
      _error = 'Error previsualizando voz: $e';
    } finally {
      await _setLoading(false);
    }
  }

  /// 🧹 Limpiar error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// 🔄 Refrescar capacidades
  Future<void> refreshCapabilities() async {
    await _setLoading(true);
    try {
      _capabilities = await _appService.getVoiceCapabilities();
      _error = null;
    } on Exception catch (e) {
      _error = 'Error refrescando capacidades: $e';
    } finally {
      await _setLoading(false);
    }
  }

  // Helpers privados
  Future<void> _setLoading(final bool loading) async {
    _isLoading = loading;
    notifyListeners();
    // Pequeño delay para permitir que la UI se actualice
    if (loading) await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  void dispose() {
    _interactionController.close();
    _responseController.close();
    super.dispose();
  }
}
