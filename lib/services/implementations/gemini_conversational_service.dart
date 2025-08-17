import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../interfaces/voice_services.dart';
import '../gemini_service.dart';
import '../../models/system_prompt.dart';
import '../../models/ai_chan_profile.dart';

/// Implementación de IA conversacional usando Gemini
class GeminiConversationalAIService implements ConversationalAIService {
  final GeminiService _geminiService;
  late SystemPrompt _systemPrompt;

  GeminiConversationalAIService() : _geminiService = GeminiService() {
    _initializeSystemPrompt();
  }

  void _initializeSystemPrompt() {
    _systemPrompt = SystemPrompt(
      profile: AiChanProfile(
        userName: 'Usuario',
        aiName: 'AI-chan',
        userBirthday: null,
        aiBirthday: null,
        biography: {'content': 'Soy AI-chan, tu asistente virtual cariñosa y amigable.'},
        appearance: {'description': 'Asistente virtual con personalidad amigable'},
        timeline: [],
      ),
      dateTime: DateTime.now(),
      instructions: {
        'content':
            'Eres AI-chan, una asistente virtual cariñosa y amigable. '
            'Responde de forma natural y conversacional. '
            'Mantén las respuestas concisas pero cálidas. '
            'Usa un tono cercano y familiar.',
      },
    );
  }

  @override
  Future<String> sendMessage({
    required String message,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? context,
  }) async {
    try {
      // Preparar historial de conversación
      final history = conversationHistory ?? [];

      // Agregar el mensaje actual
      final updatedHistory = List<Map<String, String>>.from(history);
      updatedHistory.add({'role': 'user', 'content': message});

      // Enviar a Gemini
      final response = await _geminiService.sendMessageImpl(
        updatedHistory,
        _systemPrompt,
        model: context?['model'] ?? dotenv.env['GEMINI_MODEL'] ?? 'gemini-2.5-flash',
      );

      return response.text.trim().isNotEmpty
          ? response.text.trim()
          : 'Lo siento, no pude generar una respuesta en este momento.';
    } catch (e) {
      throw Exception('Error al comunicarse con Gemini: $e');
    }
  }

  @override
  Future<List<String>> getAvailableModels() async {
    try {
      return await _geminiService.getAvailableModels();
    } catch (e) {
      throw Exception('Error al obtener modelos de Gemini: $e');
    }
  }

  @override
  bool get isAvailable {
    final primaryKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
    final fallbackKey = dotenv.env['GEMINI_API_KEY_FALLBACK']?.trim() ?? '';
    return primaryKey.isNotEmpty || fallbackKey.isNotEmpty;
  }

  @override
  Map<String, dynamic> getConfig() {
    return {
      'defaultModel': dotenv.env['GEMINI_MODEL'] ?? 'gemini-2.5-flash',
      'hasApiKey': isAvailable,
      'systemPrompt': _systemPrompt.instructions['content'],
    };
  }

  /// Actualiza el system prompt
  void updateSystemPrompt({AiChanProfile? profile, Map<String, dynamic>? instructions}) {
    _systemPrompt = SystemPrompt(
      profile: profile ?? _systemPrompt.profile,
      dateTime: DateTime.now(),
      instructions: instructions ?? _systemPrompt.instructions,
    );
  }
}
