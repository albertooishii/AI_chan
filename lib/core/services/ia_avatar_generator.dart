// ...existing imports
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/ai_runtime_guard.dart';

class IAAvatarGenerator {
  /// Genera avatar basado en la apariencia del perfil.
  /// Si [appendAvatar] es true, usa el seed del primer avatar existente
  ///   para mantener identidad y añade el nuevo avatar al histórico.
  ///   Si es false, se genera un avatar completamente nuevo y reemplaza el histórico.
  Future<AiImage> generateAvatarFromAppearance(
    final AiChanProfile bio, {
    final bool appendAvatar = false,
    final List<TimelineEntry> timeline = const [],
  }) async {
    final String forcedImageModel = Config.getDefaultImageModel();
    final String forcedTextModel = Config.getDefaultTextModel();
    Log.d(
      '[IAAvatarGenerator] Avatar: generando imagen con modelo $forcedImageModel',
    );

    // Decidir seed y preparar contexto para el prompt
    final seedToUse = _determineSeed(bio, appendAvatar);
    final promptToSend = await _buildPromptForGeneration(
      bio,
      seedToUse,
      forcedTextModel,
      timeline,
    );
    final profileForPrompt = _buildProfileForPrompt(bio, seedToUse, timeline);

    // Generar imagen con reintentos
    final imageResponse = await _generateImageWithRetries(
      promptToSend,
      profileForPrompt,
      forcedImageModel,
    );

    // Guardar y crear objeto final
    return await _saveAndCreateAvatar(imageResponse, seedToUse);
  }

  /// Determina qué seed usar según el parámetro appendAvatar
  String? _determineSeed(final AiChanProfile bio, final bool appendAvatar) {
    if (!appendAvatar) return null;
    final firstAvatar = bio.firstAvatar;
    return (firstAvatar != null && (firstAvatar.seed ?? '').isNotEmpty)
        ? firstAvatar.seed
        : null;
  }

  /// Construye el prompt final para generación, incluyendo lógica para seeds existentes
  Future<dynamic> _buildPromptForGeneration(
    final AiChanProfile bio,
    final String? seedToUse,
    final String textModel,
    final List<TimelineEntry> timeline,
  ) async {
    final basePrompt = _createBasePrompt();

    if (seedToUse == null) {
      return basePrompt;
    }

    // Para seeds existentes, generar prompt contextual usando modelo de texto
    final contextProfile = AiChanProfile(
      biography: bio.biography,
      userName: bio.userName,
      aiName: bio.aiName,
      userBirthdate: null,
      aiBirthdate: null,
      appearance: bio.appearance,
      avatars: bio.avatars,
    );

    final generatedPrompt = await _generateContextualPrompt(
      contextProfile,
      textModel,
    );
    return generatedPrompt.isNotEmpty
        ? _createPromptWithGenerated(generatedPrompt)
        : basePrompt;
  }

  /// Crea el prompt base con todas las configuraciones visuales y reglas
  Map<String, dynamic> _createBasePrompt() {
    return {
      'is_avatar': true,
      'descripcion':
          "[IMAGEN REQUERIDA]: Genera una imagen usando tu herramienta de generación de imágenes 'image_generation' teniendo en cuenta el máximo detalle de 'appearance' y la conversación actual.",
      'visual_settings': {
        'composicion': {
          'aspect_ratio': '1:1',
          'encuadre': 'cara y torso superior centrados',
          'profundidad_de_campo': 'fondo suavemente desenfocado',
        },
        'estetica': {
          'estilo':
              'selfie natural casual, divertida y espontánea, relajada y expresiva',
          'expresion':
              'sonrisa genuina, expresión alegre y natural, ojos brillantes y vivaces, actitud relajada y confiada',
          'iluminacion':
              'calida y suave, luz natural, balance de blancos cálido, contraste suave',
          'postprocesado':
              'bokeh suave, colores vibrantes pero naturales, aspecto juvenil y fresco',
        },
        'camara': {
          'objetivo_preferido': '35mm',
          'apertura': 'f/2.8-f/4',
          'iso': 'bajo',
          'enfoque': 'casual y natural, no profesional',
        },
        'parametros_tecnicos': {
          'negative_prompt':
              'Evitar poses rígidas, expresiones serias, watermark, texto, logos, firmas, baja resolución, deformaciones, elementos irreales, modificar rasgos definidos en appearance.',
        },
        'image_request': {
          'size': '1024x1024',
          'aspect_ratio': '1:1',
          'fidelity': 0.25,
        },
      },
      'identidad': {'edad_aparente': 25, 'genero': 'mujer'},
      'rasgos_fisicos': {
        'fidelidad_appearance':
            "Representa fielmente cada detalle del JSON 'appearance' con precisión milimétrica. Ojos: color, forma, tamaño, expresión, distancia, pestañas (longitud, densidad, curvatura). Cabello: color, largo, volumen, densidad, y si existe tinte/mechas verificar 'aplica=true'. Rostro: cejas, nariz, boca, dientes, orejas según especificaciones exactas. Cuerpo: altura, peso, complexión, piel, manos, pechos. Marcas: tatuajes, cicatrices, pecas, lunares en ubicación exacta.",
        'ropa_y_maquillaje':
            "Usar exactamente la ropa definida en 'appearance.conjuntos_ropa' seleccionando el conjunto más apropiado para el contexto. Respetar colores, estampados, materiales y accesorios tal como están especificados. NO modificar ni sustituir prendas. Aplicar 'maquillaje_base' de forma natural y juvenil según está definido en appearance.",
      },
      'fuentes': {
        'appearance':
            "Usar exactamente el objeto JSON 'appearance' para rasgos físicos, conjuntos_ropa, accesorios, paleta de color y marcas únicas.",
        'biography':
            "Usar 'biography' únicamente para elegir la actividad/hobby principal que aparecerá en la imagen. No extraer rasgos físicos desde la biografía si contradicen 'appearance'.",
      },
      'actividad_y_pose': {
        'seleccion_actividad':
            "Analiza detalladamente las secciones 'intereses_y_aficiones', 'horarios_actividades', 'trayectoria_profesional' e 'historia_personal' de la biografía. Extrae la actividad o hobby más característico y representativo de esta persona específica. Prioriza actividades que reflejen su personalidad geek/otaku/friki si está presente en la biografía. Usa únicamente lo que está explícitamente mencionado en estos campos, no añadas actividades genéricas.",
        'poses_y_gestos':
            'OBLIGATORIO: La pose debe ser relajada, natural y alegre. Sonrisa genuina y ojos brillantes son ESENCIALES. Si la biografía indica personalidad otaku/friki/geek, mostrar emoción y pasión por sus hobbies con gestos expresivos (peace sign, thumbs up, gestos anime). La foto debe verse como un selfie casual donde se divierte genuinamente. EVITAR COMPLETAMENTE poses formales, serias o rígidas.',
        'props_y_elementos':
            'Incluye únicamente objetos y elementos que estén directamente relacionados con las actividades, hobbies o profesión mencionados en la biografía. IMPORTANTE: Si la biografía menciona videojuegos, NO incluyas automáticamente mandos de consola visible - solo si la actividad específica lo requiere. Para personas otaku/friki/geek, prefiere elementos más sutiles y diversos relacionados con sus intereses específicos mencionados en la biografía. Los props deben ser naturales, no posados para mostrar.',
        'mascotas_y_entorno':
            "Si la sección 'mascotas' incluye animales, pueden aparecer interactuando naturalmente con la actividad. Representa exactamente las características descritas. El entorno debe ser coherente con la actividad y personalidad: si es una persona otaku/friki según su biografía, el espacio puede reflejar esa cultura de manera sutil y natural según sus intereses específicos, sin elementos que contradigan su contexto personal.",
      },
      'restricciones': [
        'Fidelidad absoluta al campo appearance del perfil',
        'NO modificar rasgos, conjuntos_ropa o accesorios definidos en appearance',
        'NO expresiones serias o rígidas',
        'NO poses profesionales o tipo foto carnet',
        'No texto en la imagen',
        'Sin marcas de agua, pie de foto ni logos, solamente la foto',
        'Sin elementos anacrónicos',
        'Sólo una persona en el encuadre',
      ],
      'salida':
          'Usa la herramienta de generación de imágenes y devuelve únicamente la imagen en base64.',
      'notas':
          "PRIORIDAD MÁXIMA: Generar una imagen ALEGRE, CASUAL y RELAJADA. La persona debe verse feliz y expresiva. Lee 'appearance' fielmente para conjuntos_ropa casual y colores. Usa 'biography' solo para elegir hobbies/actividades divertidas; prioriza 'appearance' ante contradicciones. La imagen debe tener edad aparente EXACTA = 25. EVITAR ABSOLUTAMENTE vestimenta formal o expresiones serias.",
    };
  }

  /// Genera prompt contextual usando modelo de texto
  Future<String> _generateContextualPrompt(
    final AiChanProfile profile,
    final String textModel,
  ) async {
    final basePrompt = _createBasePrompt();
    final instructions = {
      'task': 'generate_image_prompt',
      'description':
          '''Genera UN SOLO prompt de imagen listo para el generador (una frase larga, separada por comas). Debe ser SUPER-DETALLADO: extrae y utiliza toda la información visual disponible del `appearance` del `profile` adjunto (usar como única fuente de verdad para rasgos físicos, conjuntos_ropa CASUAL, colores, texturas y marcas), de la `biography` (actividad, gustos, contexto) y del `timeline` (entradas recientes) para incluir props, lugares o escenas relacionadas con acciones recientes. IMPORTANTE: La imagen debe ser ALEGRE, CASUAL y DIVERTIDA - evitar completamente ropa formal, poses serias o expresiones rígidas. Incluir sonrisa genuina y actitud relajada. No repitas el tema o estilo de avatares anteriores (avatars). Forzar edad_aparente = 25.''',
      'identidad': basePrompt['identidad'],
      'visual_settings': basePrompt['visual_settings'],
      'rasgos_fisicos': basePrompt['rasgos_fisicos'],
      'fuentes': basePrompt['fuentes'],
      'estilo_obligatorio': 'casual, alegre, divertido, sonriente, relajado',
      'actividad_y_pose': basePrompt['actividad_y_pose'],
      'restricciones': [
        'NO ropa formal (trajes, blazers, chaquetas de trabajo)',
        'NO expresiones serias o poses rígidas',
        'No texto en la imagen',
        'Sin marcas de agua',
        'Sólo una persona en el encuadre',
      ],
    };

    try {
      final systemPrompt = SystemPrompt(
        profile: profile,
        dateTime: DateTime.now(),
        instructions: instructions,
      );
      final response = await AIService.sendMessage(
        [],
        systemPrompt,
        model: textModel,
      );
      final generated =
          (response.text.isNotEmpty ? response.text : response.prompt).trim();
      Log.d(
        '[IAAvatarGenerator] Prompt generado por modelo de texto: $generated',
      );
      return generated;
    } on Exception catch (e) {
      Log.w('[IAAvatarGenerator] Prompt generator failed: $e');
      return '';
    }
  }

  /// Crea prompt usando el texto generado por el modelo
  Map<String, dynamic> _createPromptWithGenerated(final String generatedText) {
    final basePrompt = _createBasePrompt();
    return {
      'is_avatar': true,
      'descripcion':
          "[IMAGEN REQUERIDA]: Genera una imagen usando tu herramienta de generación de imágenes 'image_generation' utilizando el prompt 'image_prompt'",
      'image_prompt': generatedText,
      'visual_settings': basePrompt['visual_settings'],
      'restricciones': basePrompt['restricciones'],
      'salida': basePrompt['salida'],
    };
  }

  /// Construye el perfil que se enviará al generador
  AiChanProfile _buildProfileForPrompt(
    final AiChanProfile bio,
    final String? seedToUse,
    final List<TimelineEntry> timeline,
  ) {
    return AiChanProfile(
      biography: bio.biography,
      userName: bio.userName,
      aiName: bio.aiName,
      userBirthdate: null,
      aiBirthdate: null,
      appearance: bio.appearance,
      avatars: seedToUse != null ? bio.avatars : [],
    );
  }

  /// Genera la imagen con reintentos automáticos
  Future<AIResponse> _generateImageWithRetries(
    final dynamic promptToSend,
    final AiChanProfile profileForPrompt,
    final String imageModel,
  ) async {
    const int maxAttempts = 3;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      Log.d(
        '[IAAvatarGenerator] Avatar: intento ${attempt + 1}/$maxAttempts con $imageModel',
      );

      try {
        final systemPrompt = SystemPrompt(
          profile: profileForPrompt,
          dateTime: DateTime.now(),
          instructions: promptToSend,
        );

        final response = await AIService.sendMessage(
          [],
          systemPrompt,
          model: imageModel,
          enableImageGeneration: true,
        );

        if (response.base64.isNotEmpty) {
          Log.d(
            '[IAAvatarGenerator] Avatar: imagen obtenida en intento ${attempt + 1}',
          );
          return response;
        }
        Log.w('[IAAvatarGenerator] Avatar: intento ${attempt + 1} sin imagen');
      } on Exception catch (err) {
        if (handleRuntimeError(err, 'IAAvatarGenerator')) {
          // logged
        } else {
          Log.e(
            '[IAAvatarGenerator] Avatar: error en intento ${attempt + 1}: $err',
          );
        }
      }

      // Backoff progresivo entre intentos
      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    throw Exception('No se pudo generar el avatar tras $maxAttempts intentos.');
  }

  /// Guarda la imagen y crea el objeto AiImage final
  Future<AiImage> _saveAndCreateAvatar(
    final AIResponse imageResponse,
    final String? seedToUse,
  ) async {
    // Guardar imagen
    String? imageUrl;
    try {
      imageUrl = await saveBase64ImageToFile(
        imageResponse.base64,
        prefix: 'ai_avatar',
      );
    } on Exception {
      imageUrl = null;
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception(
        'Se generó el avatar pero no se pudo guardar la imagen en el dispositivo.',
      );
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final usedSeed = (imageResponse.seed.isNotEmpty)
        ? imageResponse.seed
        : (seedToUse ?? '');

    Log.d('[IAAvatarGenerator] Avatar: usada seed final: $usedSeed');

    return AiImage(
      seed: usedSeed,
      prompt: imageResponse.prompt,
      url: imageUrl,
      createdAtMs: nowMs,
    );
  }
}
