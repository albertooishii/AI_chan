/// Utilidades compartidas para construcción de prompts e instrucciones de imagen.
/// Contiene solo la lógica que es realmente compartida entre múltiples contextos.
class SharedPromptUtils {
  /// Obtiene las instrucciones para generación de imágenes.
  /// Usado por AI providers para generar imágenes de la IA.
  static Map<String, dynamic> getImageInstructions(final String userName) => {
    'descripcion':
        "[FOTO/IMAGEN PEDIDA POR CHAT]: $userName solicita que le envíes una foto realista casual y alegre. Genera una imagen con aspecto de fotografía tipo selfie natural tomada con móvil (alta calidad) respetando fielmente el campo 'appearance' del perfil y la conversación reciente. IMPORTANTE: La foto debe ser CASUAL, ALEGRE y EXPRESIVA con sonrisa genuina. Evitar completamente ropa formal, poses serias o expresiones rígidas. Genera una imagen usando tu herramienta de generación de imágenes 'image_generation'",
    'identidad':
        'edad_aparente = 25; mantener rasgos y proporciones realistas.',
    'visual_settings': {
      'composicion': {
        'aspect_ratio': '4:3 o 3:4 (portrait/back-ready para móvil)',
        'encuadre':
            'retrato o medio cuerpo centrado; cabeza y hombros visibles',
        'profundidad_de_campo':
            'fondo suavemente desenfocado (bokeh leve) para aislar sujeto',
      },
      'estetica': {
        'estilo':
            'selfie casual natural, divertida y espontánea, relajada y expresiva',
        'expresion':
            'sonrisa genuina, expresión alegre y natural, ojos brillantes y vivaces, actitud relajada y confiada',
        'iluminacion':
            'cálida y suave, luz natural, balance de blancos cálido; evita luz dura o sombras extremas',
        'postprocesado':
            'bokeh suave, colores vibrantes pero naturales, aspecto juvenil y fresco, sin exceso de filtros',
      },
      'camara': {
        'objetivo_preferido': '35mm equivalente',
        'apertura': 'f/2.8-f/4',
        'iso': 'bajo',
        'enfoque': 'casual y natural, no profesional',
      },
      'parametros_tecnicos': {
        'negative_prompt':
            'Evitar poses rígidas, expresiones serias, watermark, texto en la imagen, logos, baja resolución, deformaciones, manos deformes o proporciones irreales, modificar rasgos definidos en appearance.',
      },
    },
    'rasgos_fisicos': {
      'instruccion_general':
          "Extrae y respeta todos los campos relevantes del objeto 'appearance' del perfil (color de piel, rasgos faciales, peinado, ojos, marcas, etc.). Si falta algún campo, aplica un fallback realista coherente con el estilo.",
      'detalle':
          'Describe fielmente basándote en el campo appearance: rasgos faciales, peinado y color, tono de piel, ropa según el contexto (usa los conjuntos definidos en appearance.conjuntos_ropa), accesorios si están definidos en appearance, expresión facial ALEGRE con sonrisa genuina, dirección de la mirada, y pose RELAJADA. Respeta completamente la vestimenta, estampados y accesorios tal como están definidos en appearance sin modificar ni añadir elementos. Presta especial atención a las manos: representarlas con dedos proporcionados y en poses naturales; evita manos deformes o poco realistas. Si aparece una pantalla o dispositivo con botones en la escena, asegúrate de que la pantalla esté encendida y sea visible.',
    },
    'restricciones': [
      'Respetar fielmente el campo appearance del perfil',
      'NO inventar rasgos o ropa no definidos en appearance',
      'NO expresiones serias o rígidas',
      'NO poses profesionales o tipo foto carnet',
      'No texto en la imagen',
      'Sin marcas de agua',
      'Solo una persona en el encuadre salvo que se especifique lo contrario.',
    ],
  };

  /// Obtiene los metadatos para procesamiento de imágenes.
  static Map<String, dynamic> getImageMetadata(final String userName) => {
    'tipo': 'selfie_casual',
    'usuario_solicitante': userName,
    'categoria': 'autorretrato',
    'estilo_preferido': 'natural_expresivo',
    'calidad_esperada': 'alta',
    'formato_sugerido': 'portrait',
  };
}
