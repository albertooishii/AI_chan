import 'dart:convert';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/ai_runtime_guard.dart';

class IAAvatarGenerator {
  /// Genera una imagen (avatar) a partir del JSON de apariencia y la guarda.
  /// Devuelve un objeto AiImage con seed/prompt/url.
  Future<AiImage> generateAvatarFromAppearance(
    AiChanProfile bio,
    Map<String, dynamic> appearance, {
    AIService? aiService,
    Future<String?> Function(String base64, {String prefix})? saveImageFunc,
    String? seedOverride,
  }) async {
    final String forcedImageModel = Config.getDefaultImageModel();
    Log.d('[IAAvatarGenerator] Avatar: generando imagen con modelo $forcedImageModel');

    final imagePrompt =
        '''Usa la herramienta de generación de imágenes y devuelve únicamente la imagen en base64.
Genera una imagen hiperrealista cuadrada (1:1) centrada en la cara y torso superior, coherente con este JSON de apariencia:
${jsonEncode(appearance)}
Recuerda: la imagen debe representar a una mujer joven de 25 años (edad aparente = 25). SOLO devuelve la imagen en base64 en la respuesta.''';

    AIResponse imageResponse = AIResponse(text: '', base64: '', seed: '', prompt: '');
    const int maxImageAttemptsPerModel = 3;
    for (int attempt = 0; attempt < maxImageAttemptsPerModel; attempt++) {
      Log.d('[IAAvatarGenerator] Avatar: intento ${attempt + 1}/$maxImageAttemptsPerModel con $forcedImageModel');
      try {
        // Build SystemPrompt with optional avatar seed to allow regenerations that
        // re-use the same image id (seed) when requested.
        final profileForPrompt = AiChanProfile(
          biography: bio.biography,
          userName: bio.userName,
          aiName: bio.aiName,
          userBirthday: null,
          aiBirthday: null,
          appearance: appearance,
          avatars: seedOverride != null ? [AiImage(seed: seedOverride)] : null,
          timeline: [],
        );

        final systemPromptImage = SystemPrompt(
          profile: profileForPrompt,
          dateTime: DateTime.now(),
          instructions: {'raw': imagePrompt},
        );

        final resp = await (aiService != null
            ? aiService.sendMessageImpl([], systemPromptImage, model: forcedImageModel, enableImageGeneration: true)
            : AIService.sendMessage([], systemPromptImage, model: forcedImageModel, enableImageGeneration: true));

        if (resp.base64.isNotEmpty) {
          imageResponse = resp;
          Log.d('[IAAvatarGenerator] Avatar: imagen obtenida en intento ${attempt + 1}');
          break;
        }
        Log.w('[IAAvatarGenerator] Avatar: intento ${attempt + 1} sin imagen');
      } catch (err) {
        if (handleRuntimeError(err, 'IAAvatarGenerator')) {
          // logged
        } else {
          Log.e('[IAAvatarGenerator] Avatar: error en intento ${attempt + 1}: $err');
        }
      }
    }

    if (imageResponse.base64.isEmpty) {
      throw Exception('No se pudo generar el avatar tras $maxImageAttemptsPerModel intentos.');
    }

    // Guardar imagen
    String? imageUrl;
    try {
      imageUrl = await (saveImageFunc != null
          ? saveImageFunc(imageResponse.base64, prefix: 'ai_avatar')
          : saveBase64ImageToFile(imageResponse.base64, prefix: 'ai_avatar'));
    } catch (e) {
      imageUrl = null;
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Se generó el avatar pero no se pudo guardar la imagen en el dispositivo.');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final usedSeed = seedOverride ?? imageResponse.seed;
    return AiImage(seed: usedSeed, prompt: imageResponse.prompt, url: imageUrl, createdAtMs: nowMs);
  }
}
