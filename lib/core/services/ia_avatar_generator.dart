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

    final Map<String, dynamic> basePromptMap = {
      // Marca explícita para facilitar la detección en el servicio de envío
      // Indica que este prompt es para generar un AVATAR/foto de personaje
      "image_type": "avatar",
      "is_avatar": true,
      "descripcion":
          "Prompt JSON para generar avatar estilo foto divertida de Instagram. Devuelve SOLO la imagen en base64, sin texto ni metadatos.",
      "composicion": {
        "aspect_ratio": "1:1",
        "encuadre": "cara y torso superior centrados",
        "profundidad_de_campo": "fondo suavemente desenfocado",
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
      "estetica": {
        "estilo": "instagram portrait, divertida y natural",
        "iluminacion": "calida, direccional, balance de blancos cálido, contraste medio-alto",
        "postprocesado":
            "bokeh, viñeteado sutil, nitidez en ojos, suavizado de piel realista, colores ligeramente saturados",
      },
      "camara": {"objetivo_preferido": "50mm", "apertura": "f/1.8-f/2.8", "iso": "bajo-medio"},
      "entorno":
          "Fondo coherente con la actividad descrita en la biografía. Evitar logos, marcas y texto. Mantener props y entorno contemporáneos; no incluir ejemplos literales que el modelo pueda renderizar como texto u objetos exactos.",
      "restricciones": [
        "No texto en la imagen",
        "Sin marcas de agua ni logos",
        "Sin elementos anacrónicos",
        "Sólo una persona en el encuadre",
        "Evitar poses sexualizadas; mantener naturalidad y respeto",
      ],
      "salida": "Usa la herramienta de generación de imágenes y devuelve únicamente la imagen en base64, sin texto.",
      "parametros_recomendados": {
        "negative_prompt":
            "Evitar watermark, texto, logos, firmas, baja resolución, deformaciones o elementos irreales.",
        "nota":
            "Si el backend admite parámetros técnicos (steps, sampler, cfg_scale), configúralos según su política; no se requieren valores literales aquí.",
      },
      "notas":
          "Lee 'appearance' fielmente para ropa, colores, texturas y accesorios. Usa 'biography' solo para elegir la actividad y contexto; prioriza 'appearance' ante contradicciones. La imagen debe tener edad aparente EXACTA = 25.",
      "image_request": {"size": "1024x1024", "aspect_ratio": "1:1", "fidelity": 0.25},
    };

    // Construir identity_summary dinámicamente copiando los campos listados
    // en 'rasgos_fisicos.campos_a_usar' desde el objeto appearance.
    try {
      final campos = (basePromptMap['rasgos_fisicos'] as Map<String, dynamic>)['campos_a_usar'] as List<dynamic>;
      final Map<String, dynamic> dynSummary = {};
      for (final c in campos) {
        final key = c.toString();
        if (appearance.containsKey(key)) dynSummary[key] = appearance[key];
      }
      basePromptMap['identity_summary'] = dynSummary;
    } catch (_) {
      // If something fails, fallback a un resumen mínimo
      basePromptMap['identity_summary'] = {
        'edad_aparente': appearance['edad_aparente'],
        'genero': appearance['genero'],
      };
    }

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

      // Construir un pequeño resumen de identidad para enviar al motor en
      // lugar de la seed como instrucción rígida (preserva identidad sin forzar edits)
      // Usar el resumen de identidad ya incluido en basePromptMap
      final identitySummary = basePromptMap['identity_summary'] as Map<String, dynamic>;

      // Bloque de variación simplificado: evitar instrucciones que sugieran
      // ediciones mínimas sobre la imagen previa. Pedimos una foto NUEVA y
      // distinta, conservando sólo la referencia facial mínima.
      final variationBlock = {
        'variacion_por_seed': {
          'mantener_identidad_facial': true,
          'identity_summary': identitySummary,
          'completely_new_scene': true,
          'cambio_ropa_y_fondo': true,
          'ensure_distinct': true,
          'instruccion':
              "Genera una FOTO COMPLETAMENTE NUEVA en otra ubicación, con ropa distinta y realizando una actividad diferente. Usa 'identity_summary' SOLO para mantener una mínima reconocibilidad facial; no reutilices ropa, accesorios, fondo ni composiciones anteriores. Devuelve únicamente la imagen en base64 sin texto ni marcas de agua.",
        },
      };

      // Construir un prompt de variación reducido — NO unir todo el basePromptMap
      // para evitar arrastrar 'entorno' o 'actividad_y_pose' que causaban fondos
      // repetidos similares. Conservamos solo los campos necesarios y añadimos
      // el bloque de variación.
      final variationPrompt = <String, dynamic>{
        'image_type': basePromptMap['image_type'],
        'is_avatar': basePromptMap['is_avatar'],
        'descripcion': basePromptMap['descripcion'],
        'composicion': basePromptMap['composicion'],
        'rasgos_fisicos': basePromptMap['rasgos_fisicos'],
        'estetica': basePromptMap['estetica'],
        'camara': basePromptMap['camara'],
        'restricciones': basePromptMap['restricciones'],
        'salida': basePromptMap['salida'],
        'image_request': basePromptMap['image_request'],
      };

      variationPrompt.addAll(variationBlock);
      promptToSend = variationPrompt;
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
      avatars: null,
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
