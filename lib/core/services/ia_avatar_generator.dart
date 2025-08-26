// ...existing imports
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
  Future<AiImage> generateAvatarFromAppearance(AiChanProfile bio, {bool appendAvatar = false}) async {
    final String forcedImageModel = Config.getDefaultImageModel();
    final String forcedTextModel = Config.getDefaultTextModel();
    Log.d('[IAAvatarGenerator] Avatar: generando imagen con modelo $forcedImageModel');

    // Obtener la apariencia desde el perfil; los llamadores deben actualizar
    // el perfil (bio) con la nueva appearance antes de llamar a esta función
    final Map<String, dynamic> appearance = bio.appearance;

    // Usamos el wrapper estático `AIService.sendMessage` que ya respeta
    // `AIService.testOverride` para tests y realiza la resolución del runtime
    // internamente. Evitamos usar la fábrica `runtime_factory` directamente
    // desde aquí para reducir acoplamiento.

    final Map<String, dynamic> basePromptMap = {
      // Marca explícita para facilitar la detección en el servicio de envío
      // Indica que este prompt es para generar un AVATAR/foto de personaje
      "is_avatar": true,
      "descripcion":
          "[IMAGEN REQUERIDA]: Genera una imagen usando tu herramienta de generación de imágenes 'image_generation' teniendo en cuenta el máximo detalle de 'appearance' y la conversación actual.",
      "visual_settings": {
        "composicion": {
          "aspect_ratio": "1:1",
          "encuadre": "cara y torso superior centrados",
          "profundidad_de_campo": "fondo suavemente desenfocado",
        },
        "estetica": {
          "estilo": "instagram portrait, divertida y natural",
          "iluminacion": "calida, direccional, balance de blancos cálido, contraste medio-alto",
          "postprocesado":
              "bokeh, viñeteado sutil, nitidez en ojos, suavizado de piel realista, colores ligeramente saturados",
        },
        "camara": {"objetivo_preferido": "50mm", "apertura": "f/1.8-f/2.8", "iso": "bajo-medio"},
        "parametros_tecnicos": {
          "negative_prompt":
              "Evitar watermark, texto, logos, firmas, baja resolución, deformaciones o elementos irreales.",
        },
        "image_request": {"size": "1024x1024", "aspect_ratio": "1:1", "fidelity": 0.25},
      },
      "identidad": {"edad_aparente": 25, "genero": "mujer"},
      "rasgos_fisicos": {
        "instruccion_general":
            "Representa fielmente los rasgos físicos descritos en 'appearance'. Usa las claves exactas del JSON de apariencia para mapear cada atributo visual.",
        "campos_a_usar": [
          "edad_aparente",
          "genero",
          "origen_etnico",
          "altura",
          "peso",
          "complexion",
          "color_piel",
          "ojos",
          "cejas",
          "nariz",
          "boca",
          "dientes",
          "orejas",
          "cabello",
          "manos",
          "piel",
          "pechos",
          "piernas",
          "tatuajes",
          "cicatrices",
          "pecas",
          "lunares",
          "arrugas",
          "paleta_color",
          "maquillaje_base",
          "expresion_general",
          "rasgos_unicos",
        ],
        "detalle":
            "Para cada campo visual, aplica las especificaciones exactas: medidas/proporciones para 'altura' y 'peso', 'complexion' como forma corporal, 'ojos' (color, forma, tamaño, expresión, distancia entre ojos, pestañas), cejas (forma/grosor), nariz (forma/tamaño), boca (forma/labios/expresión), cabello (color/largo/peinado/volumen/textura) y marcas (tatuajes/cicatrices/pecas/lunares) en ubicación y tamaño indicados. Ajusta la iluminación y el encuadre para resaltar el rostro y respetar proporciones reales. No inventes rasgos fuera de los campos listados; si algún campo está vacío, usa un fallback realista y coherente con 'estilo' y 'paleta_color'.",
      },
      "fuentes": {
        "appearance":
            "Usar exactamente el objeto JSON 'appearance' para rasgos físicos, ropa, accesorios, paleta de color y marcas únicas.",
        "biography":
            "Usar 'biography' únicamente para elegir la actividad/hobby principal que aparecerá en la imagen. No extraer rasgos físicos desde la biografía si contradicen 'appearance'.",
      },
      "instrucciones_apariencia":
          "La lista 'ropa' en 'appearance' contiene exactamente nueve conjuntos en este orden: 1) Trabajo, 2) Ocio muy casual, 3) Fiesta normal, 4) Fiesta cultural, 5) Diario primavera, 6) Diario verano, 7) Diario otoño, 8) Diario invierno, 9) Pijama. Selecciona el conjunto que mejor concuerde con la actividad indicada en la biografía. Si no hay correspondencia clara, usa el conjunto 2 (Ocio muy casual). Reproducir texturas, materiales y colores tal como aparecen en 'appearance'. Mostrar tatuajes, cicatrices o pecas en la ubicación y tamaño descritos si existen.",
      "actividad_y_pose":
          "Extrae la actividad principal desde biography.intereses_y_aficiones o biography.resumen_breve. Muestra a la persona realizando esa actividad con expresión de disfrute (sonrisa natural, mirada enfocada, gestos coherentes con la acción). Añade elementos o props coherentes según la actividad descrita en la biografía, evitando listar ejemplos literales que el modelo pueda reproducir textualmente en la imagen.",
      "entorno":
          "Fondo coherente con la actividad descrita en la biografía. Evitar logos, marcas y texto. Mantener props y entorno contemporáneos; no incluir ejemplos literales que el modelo pueda renderizar como texto u objetos exactos.",
      "restricciones": [
        "No texto en la imagen",
        "Sin marcas de agua, pie de foto ni logos, solamente la foto",
        "Sin elementos anacrónicos",
        "Sólo una persona en el encuadre",
      ],
      "salida": "Usa la herramienta de generación de imágenes y devuelve únicamente la imagen en base64, sin texto.",
      "notas":
          "Lee 'appearance' fielmente para ropa, colores, texturas y accesorios. Usa 'biography' solo para elegir la actividad y contexto; prioriza 'appearance' ante contradicciones. La imagen debe tener edad aparente EXACTA = 25.",
    };

    AIResponse imageResponse = AIResponse(text: '', base64: '', seed: '', prompt: '');
    const int maxImageAttemptsPerModel = 3;

    // Decide seed internamente: si appendAvatar==true y el perfil tiene avatars,
    // usamos la seed del primer avatar para mantener identidad. Si no, generamos fresh.
    String? seedToUse;
    if (appendAvatar) {
      final firstAvatar = bio.firstAvatar;
      seedToUse = (firstAvatar != null && (firstAvatar.seed ?? '').isNotEmpty) ? firstAvatar.seed : null;
    } else {
      seedToUse = null;
    }

    // Preparar contenedor para posibles últimas entradas del timeline que se
    // incluirán en el profileForPrompt cuando se reutilice una seed.
    List<TimelineEntry> recentTimelineEntries = [];

    // Prompt final (no cambia entre intentos). Si hay seed, añadimos instrucciones específicas
    // de variación que incluyan el resumen de avatares previos para evitar replicarlos.
    dynamic promptToSend;
    if (seedToUse != null) {
      // No recopilamos ni enviamos avatares previos para evitar señales que
      // produzcan repeticiones del fondo, ropa o props anteriores.
      // Construir lista de hasta 5 TimelineEntry más recientes para incluirla
      // en el profileForPrompt (no en el variationBlock). Mantener objetos
      // TimelineEntry para que el profileForPrompt sea consistente.
      if (bio.timeline.isNotEmpty) {
        final sorted = List<TimelineEntry>.from(bio.timeline);
        sorted.sort((a, b) {
          final aMs = DateTime.tryParse(a.startDate ?? '')?.millisecondsSinceEpoch ?? 0;
          final bMs = DateTime.tryParse(b.startDate ?? '')?.millisecondsSinceEpoch ?? 0;
          return bMs.compareTo(aMs);
        });
        recentTimelineEntries = sorted.take(5).toList();
      }

      // Construir profileForPrompt mínimo para pasar contexto al generador
      final profileForPromptGen = AiChanProfile(
        biography: bio.biography,
        userName: bio.userName,
        aiName: bio.aiName,
        userBirthday: null,
        aiBirthday: null,
        appearance: appearance,
        avatars: bio.avatars,
        timeline: recentTimelineEntries,
      );

      // Preparar instrucciones para generar el prompt textual
      final generatorInstructions = {
        'task': 'generate_image_prompt',
        'description':
            '''Genera UN SOLO prompt de imagen listo para el generador (una frase larga, separada por comas). Debe ser SUPER-DETALLADO: extrae y utiliza toda la información visual disponible del `appearance` del `profile` adjunto (usar como única fuente de verdad para rasgos físicos, ropa, colores, texturas y marcas), de la `biography` (actividad, gustos, contexto) y del `timeline` (entradas recientes) para incluir props, lugares o escenas relacionadas con acciones recientes. No repitas el tema o estilo de avatares anteriores (avatars) y produce un concepto notablemente diferente mientras mantienes los rasgos faciales esenciales si se utiliza continuidad de semilla. No inventes campos ni claves que no existan. Forzar edad_aparente = 25. Añade una cláusula negativa corta: "sin texto, sin logos, sin marcas de agua, sin pie de foto, sin distorsiones, sin manos deformes; asegurar que la pantalla y los botones estén correctamente orientados y visibles hacia la persona que lo está usando (no hacia la parte trasera)". Devuelve SOLO el prompt en una línea, sin explicaciones, sin metadatos ni enumeraciones de campos. Si falta algún detalle en `appearance`, usa un fallback realista sin inventar valores concretos.''',
        'identidad': basePromptMap['identidad'],
        'restricciones': basePromptMap['restricciones'],
      };

      // Enviar petición al servicio de IA para generar el prompt textual
      String generatedPromptText = '';
      try {
        final systemPromptGen = SystemPrompt(
          profile: profileForPromptGen,
          dateTime: DateTime.now(),
          instructions: generatorInstructions,
        );
        final genResp = await AIService.sendMessage(
          [],
          systemPromptGen,
          model: forcedTextModel,
          enableImageGeneration: false,
        );
        // genResp.text is non-nullable; prefer it when non-empty, otherwise use prompt
        generatedPromptText = (genResp.text.isNotEmpty ? genResp.text : (genResp.prompt)).trim();
        // Log para depuración: ver el prompt textual generado por el modelo de texto
        Log.d('[IAAvatarGenerator] Prompt generado por modelo de texto: $generatedPromptText');
      } catch (e) {
        Log.w('[IAAvatarGenerator] Prompt generator failed: $e');
      }

      if (generatedPromptText.isNotEmpty) {
        // Usar el prompt textual generado como instrucción principal para
        // la generación de imagen. Conservamos restricciones y metadata.
        promptToSend = {
          "is_avatar": true,
          "descripcion":
              "[IMAGEN REQUERIDA]: Genera una imagen usando tu herramienta de generación de imágenes 'image_generation' utilizando el prompt 'image_prompt'",
          'image_prompt': generatedPromptText,
          'visual_settings': basePromptMap['visual_settings'],
          'restricciones': basePromptMap['restricciones'],
          'salida': basePromptMap['salida'],
        };
      } else {
        Log.w('[IAAvatarGenerator] Prompt generator returned empty; usando basePromptMap como fallback');
        promptToSend = basePromptMap;
      }
    } else {
      promptToSend = basePromptMap;
    }

    // Construir profileForPrompt también fuera del bucle (no cambia entre intentos)
    final profileForPrompt = AiChanProfile(
      biography: bio.biography,
      userName: bio.userName,
      aiName: bio.aiName,
      userBirthday: null,
      aiBirthday: null,
      appearance: appearance,
      avatars: seedToUse != null ? bio.avatars : [],
      timeline: seedToUse != null ? recentTimelineEntries : [],
    );

    for (int attempt = 0; attempt < maxImageAttemptsPerModel; attempt++) {
      Log.d('[IAAvatarGenerator] Avatar: intento ${attempt + 1}/$maxImageAttemptsPerModel con $forcedImageModel');
      try {
        final systemPromptImage = SystemPrompt(
          profile: profileForPrompt,
          dateTime: DateTime.now(),
          instructions: promptToSend,
        );

        final resp = await AIService.sendMessage(
          [],
          systemPromptImage,
          model: forcedImageModel,
          enableImageGeneration: true,
        );

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

  // generateAvatarWithRetries was removed: callers should use
  // `generateAvatarFromAppearance` directly. The internal retry logic
  // is implemented inside `generateAvatarFromAppearance`.
}
