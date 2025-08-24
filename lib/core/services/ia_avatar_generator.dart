import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/ai_runtime_guard.dart';

class IAAvatarGenerator {
  /// Genera una imagen (avatar) a partir del JSON de apariencia y la guarda.
  /// Devuelve un objeto AiImage con seed/prompt/url.
  ///
  /// Parámetros:
  /// - [appendAvatar]: si es true, reutiliza la seed del primer avatar (si existe)
  ///   para mantener identidad y añade el nuevo avatar al histórico.
  ///   Si es false, se genera un avatar completamente nuevo y reemplaza el histórico.
  Future<AiImage> generateAvatarFromAppearance(
    AiChanProfile bio, {
    AIService? aiService,
    bool appendAvatar = false,
  }) async {
    final String forcedImageModel = Config.getDefaultImageModel();
    Log.d('[IAAvatarGenerator] Avatar: generando imagen con modelo $forcedImageModel');

    // Obtener la apariencia desde el perfil; los llamadores deben actualizar
    // el perfil (bio) con la nueva appearance antes de llamar a esta función
    final Map<String, dynamic> appearance = bio.appearance;

    // Construir prompt base una sola vez para evitar reconstrucción en cada intento
    final String baseImagePrompt = '''
      Usa la herramienta de generación de imágenes y devuelve únicamente la imagen en base64.
      Genera una imagen hiperrealista cuadrada (1:1) centrada en la cara y torso superior, coherente con su apariencia física que está en el campo 'appearance'.
      La imagen debe mostrar a la IA realizando una actividad que le guste (elige la actividad a partir de 'biography'). La pose y la expresión deben transmitir que está disfrutando de esa actividad (sonrisa natural, mirada enfocada, gestos suaves).
      Viste ropa coherente con los campos de `appearance` (usa prendas, estilo, colores y accesorios especificados allí).
      Recuerda: la imagen debe representar a una mujer joven de 25 años (edad aparente = 25). Evita texto, marcas de agua y elementos anacrónicos. SOLO devuelve la imagen en base64 en la respuesta.
    ''';

    AIResponse imageResponse = AIResponse(text: '', base64: '', seed: '', prompt: '');
    const int maxImageAttemptsPerModel = 3;

    // Decide seed internamente: si appendAvatar==true y el perfil tiene avatars,
    // usamos la seed del primer avatar para mantener identidad. Si no, generamos fresh.
    String? seedToUse;
    if (appendAvatar && bio.avatars != null && bio.avatars!.isNotEmpty && (bio.avatars!.first.seed ?? '').isNotEmpty) {
      seedToUse = bio.avatars!.first.seed;
    } else {
      seedToUse = null;
    }

    // Prompt final (no cambia entre intentos) — mejora rendimiento al no concatenar en cada loop
    final String promptToSend = seedToUse != null
        ? '$baseImagePrompt\nGenera una NUEVA imagen manteniendo la identidad facial pero variando la ropa, cabello, la pose y el entorno según las que hay disponibles en appearance. SOLO devuelve la imagen en base64 en la respuesta.'
        : baseImagePrompt;

    // Construir profileForPrompt también fuera del bucle (no cambia entre intentos)
    final profileForPrompt = AiChanProfile(
      biography: bio.biography,
      userName: bio.userName,
      aiName: bio.aiName,
      userBirthday: null,
      aiBirthday: null,
      appearance: appearance,
      avatars: seedToUse != null ? bio.avatars : null,
      timeline: [],
    );

    for (int attempt = 0; attempt < maxImageAttemptsPerModel; attempt++) {
      Log.d('[IAAvatarGenerator] Avatar: intento ${attempt + 1}/$maxImageAttemptsPerModel con $forcedImageModel');
      try {
        final systemPromptImage = SystemPrompt(
          profile: profileForPrompt,
          dateTime: DateTime.now(),
          instructions: {'raw': promptToSend},
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

      // Backoff progresivo entre intentos para evitar ráfagas
      if (attempt < maxImageAttemptsPerModel - 1) {
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (imageResponse.base64.isEmpty) {
      throw Exception('No se pudo generar el avatar tras $maxImageAttemptsPerModel intentos.');
    }

    // Guardar imagen
    String? imageUrl;
    try {
      imageUrl = await saveBase64ImageToFile(imageResponse.base64, prefix: 'ai_avatar');
    } catch (e) {
      imageUrl = null;
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Se generó el avatar pero no se pudo guardar la imagen en el dispositivo.');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Prefer the seed returned by the image service when available. Si la API
    // devolvió una nueva seed, usarla; si no, usar la seed interna decidida.
    final String usedSeed = (imageResponse.seed.isNotEmpty) ? imageResponse.seed : (seedToUse ?? '');

    Log.d('[IAAvatarGenerator] Avatar: usada seed final: $usedSeed');

    final avatar = AiImage(seed: usedSeed, prompt: imageResponse.prompt, url: imageUrl, createdAtMs: nowMs);

    // Nota: no modificamos ni persistimos onboardingData aquí. El llamador
    // deberá incorporar el avatar a su `AiChanProfile` y persistir si procede.
    return avatar;
  }

  /// Wrapper que reintenta la generación de avatar hasta [maxAttempts].
  /// No muestra dialogs ni persiste nada; lanza excepción si no consigue una imagen.
  Future<AiImage> generateAvatarWithRetries(
    AiChanProfile bio, {
    AIService? aiService,
    bool appendAvatar = false,
    int maxAttempts = 3,
    Duration retryDelay = const Duration(milliseconds: 700),
  }) async {
    Exception? lastErr;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final avatar = await generateAvatarFromAppearance(bio, aiService: aiService, appendAvatar: appendAvatar);
        return avatar;
      } catch (e) {
        lastErr = Exception('Intento $attempt falló: $e');
        Log.w('[IAAvatarGenerator] generateAvatarWithRetries intento $attempt fallido: $e');
        if (attempt < maxAttempts) await Future.delayed(retryDelay * attempt);
      }
    }
    throw Exception('No se pudo generar el avatar tras $maxAttempts intentos. Último error: $lastErr');
  }
}
