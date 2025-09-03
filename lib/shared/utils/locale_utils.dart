import 'package:ai_chan/shared/constants/countries_es.dart';

class LocaleUtils {
  // Nombre del país en español (simplificado)
  static String countryNameEs(String? iso2, {String fallback = 'tu país'}) {
    if (iso2 == null || iso2.trim().isEmpty) return fallback;
    return CountriesEs.codeToName[iso2.toUpperCase()] ?? fallback;
  }

  // Idioma principal del país (en español)
  static String languageNameEsForCountry(
    String? iso2, {
    String fallback = 'Español',
  }) {
    if (iso2 == null || iso2.trim().isEmpty) return fallback;
    switch (iso2.toUpperCase()) {
      // Europa occidental y central
      case 'ES':
        return 'Español';
      case 'FR':
        return 'Francés';
      case 'IT':
        return 'Italiano';
      case 'PT':
        return 'Portugués';
      case 'DE':
        return 'Alemán';
      case 'GB':
        return 'Inglés';
      case 'IE':
        return 'Inglés';
      case 'BE':
        return 'Neerlandés o Francés';
      case 'NL':
        return 'Neerlandés';
      case 'CH':
        return 'Alemán, Francés o Italiano';
      case 'AT':
        return 'Alemán';
      case 'GR':
        return 'Griego';
      case 'PL':
        return 'Polaco';
      case 'HU':
        return 'Húngaro';
      case 'CZ':
        return 'Checo';
      case 'NO':
        return 'Noruego';
      case 'SE':
        return 'Sueco';
      case 'FI':
        return 'Finés o Sueco';
      case 'DK':
        return 'Danés';
      case 'IS':
        return 'Islandés';
      case 'RU':
        return 'Ruso';
      case 'UA':
        return 'Ucraniano';
      case 'RO':
        return 'Rumano';
      case 'BG':
        return 'Búlgaro';
      case 'HR':
        return 'Croata';
      case 'RS':
        return 'Serbio';
      case 'TR':
        return 'Turco';
      case 'MT':
        return 'Maltés o Inglés';
      case 'AD':
        return 'Catalán';
      case 'SI':
        return 'Esloveno';
      case 'SK':
        return 'Eslovaco';
      case 'ME':
        return 'Montenegrino';
      case 'BA':
        return 'Bosnio, Serbio o Croata';
      case 'EE':
        return 'Estonio';
      case 'LV':
        return 'Letón';

      // Américas
      case 'US':
        return 'Inglés';
      case 'CA':
        return 'Inglés o Francés';
      case 'MX':
        return 'Español';
      case 'CU':
        return 'Español';
      case 'DO':
        return 'Español';
      case 'PR':
        return 'Español o Inglés';
      case 'CR':
        return 'Español';
      case 'PA':
        return 'Español';
      case 'GT':
        return 'Español';
      case 'HN':
        return 'Español';
      case 'SV':
        return 'Español';
      case 'NI':
        return 'Español';
      case 'CO':
        return 'Español';
      case 'VE':
        return 'Español';
      case 'EC':
        return 'Español';
      case 'PE':
        return 'Español';
      case 'BO':
        return 'Español';
      case 'CL':
        return 'Español';
      case 'AR':
        return 'Español';
      case 'BR':
        return 'Portugués';
      case 'PY':
        return 'Español o Guaraní';
      case 'UY':
        return 'Español';
      case 'HT':
        return 'Francés o Criollo haitiano';
      case 'JM':
        return 'Inglés';

      // África
      case 'MA':
        return 'Árabe';
      case 'DZ':
        return 'Árabe';
      case 'TN':
        return 'Árabe';
      case 'EG':
        return 'Árabe';
      case 'SD':
        return 'Árabe';
      case 'LY':
        return 'Árabe';
      case 'SN':
        return 'Francés';
      case 'GM':
        return 'Inglés';
      case 'GH':
        return 'Inglés';
      case 'NG':
        return 'Inglés';
      case 'ET':
        return 'Amárico';
      case 'KE':
        return 'Inglés o Suajili';
      case 'TZ':
        return 'Suajili o Inglés';
      case 'UG':
        return 'Inglés o Suajili';
      case 'CD':
        return 'Francés';
      case 'AO':
        return 'Portugués';
      case 'MZ':
        return 'Portugués';
      case 'MG':
        return 'Malgache o Francés';
      case 'ZA':
        return 'Inglés, Zulú o Afrikáans';
      case 'GQ':
        return 'Español o Francés';

      // Asia
      case 'CN':
        return 'Chino';
      case 'JP':
        return 'Japonés';
      case 'KR':
        return 'Coreano';
      case 'KP':
        return 'Coreano';
      case 'IN':
        return 'Hindi o Inglés';
      case 'PK':
        return 'Urdu o Inglés';
      case 'NP':
        return 'Nepalí';
      case 'LK':
        return 'Cingalés o Tamil';
      case 'TH':
        return 'Tailandés';
      case 'VN':
        return 'Vietnamita';
      case 'KH':
        return 'Jemer';
      case 'LA':
        return 'Lao';
      case 'MM':
        return 'Birmano';
      case 'MY':
        return 'Malayo';
      case 'SG':
        return 'Inglés o Chino';
      case 'ID':
        return 'Indonesio';
      case 'PH':
        return 'Filipino o Inglés';
      case 'IL':
        return 'Hebreo o Árabe';

      // Oceanía
      case 'AU':
        return 'Inglés';
      case 'NZ':
        return 'Inglés o Maorí';
      case 'FJ':
        return 'Inglés o Fiyiano';
      default:
        return fallback;
    }
  }

  // Construye una lista de idiomas razonable para la IA según su país y el del usuario
  static String languagesListForPair({
    String? aiCountryCode,
    String? userCountryCode,
  }) {
    final Set<String> langs = {};
    final aiLang = languageNameEsForCountry(aiCountryCode);
    final userLang = languageNameEsForCountry(userCountryCode);
    langs.add(aiLang);
    langs.add(userLang);
    // Inglés como comodín global
    langs.add('Inglés');
    return langs.join(', ');
  }

  // Convierte un código ISO2 en emoji de bandera (usa indicadores regionales Unicode)
  static String flagEmojiForCountry(String? iso2) {
    if (iso2 == null || iso2.length != 2) return '';
    final code = iso2.toUpperCase();
    final int base = 0x1F1E6; // Regional Indicator Symbol Letter A
    final int aCode = 'A'.codeUnitAt(0);
    final int first = base + (code.codeUnitAt(0) - aCode);
    final int second = base + (code.codeUnitAt(1) - aCode);
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  // Devuelve una lista de códigos de idioma oficiales/uso común para un país ISO2.
  // Los códigos intentan usar la forma 'll-CC' (por ejemplo 'es-ES', 'ja-JP') cuando es posible.
  // Si no se conoce una correspondencia específica, devuelve una lista vacía.
  // Esta función está pensada para pasar a servicios TTS que aceptan tanto 'ja' como 'ja-JP'.
  static List<String> officialLanguageCodesForCountry(String? iso2) {
    if (iso2 == null || iso2.trim().isEmpty) return <String>[];
    switch (iso2.toUpperCase()) {
      // Europa occidental y central
      case 'ES':
        // España tiene varios idiomas cooficiales según la comunidad autónoma
        return ['es-ES', 'ca-ES', 'eu-ES', 'gl-ES', 'oc-ES'];
      case 'FR':
        return ['fr-FR'];
      case 'IT':
        return ['it-IT'];
      case 'PT':
        return ['pt-PT'];
      case 'DE':
        return ['de-DE'];
      case 'GB':
        return ['en-GB'];
      case 'IE':
        return ['en-IE'];
      case 'BE':
        return ['nl-BE', 'fr-BE'];
      case 'NL':
        return ['nl-NL'];
      case 'CH':
        return ['de-CH', 'fr-CH', 'it-CH'];
      case 'AT':
        return ['de-AT'];
      case 'GR':
        return ['el-GR'];
      case 'PL':
        return ['pl-PL'];
      case 'HU':
        return ['hu-HU'];
      case 'CZ':
        return ['cs-CZ'];
      case 'NO':
        return ['no-NO'];
      case 'SE':
        return ['sv-SE'];
      case 'FI':
        return ['fi-FI', 'sv-FI'];
      case 'DK':
        return ['da-DK'];
      case 'IS':
        return ['is-IS'];
      case 'RU':
        return ['ru-RU'];
      case 'UA':
        return ['uk-UA'];
      case 'RO':
        return ['ro-RO'];
      case 'BG':
        return ['bg-BG'];
      case 'HR':
        return ['hr-HR'];
      case 'RS':
        return ['sr-RS'];
      case 'TR':
        return ['tr-TR'];
      case 'MT':
        return ['mt-MT', 'en-MT'];
      case 'AD':
        return ['ca-AD', 'es-AD'];
      case 'SI':
        return ['sl-SI'];
      case 'SK':
        return ['sk-SK'];
      case 'ME':
        return ['sr-ME', 'cnr-ME'];
      case 'BA':
        return ['bs-BA', 'sr-BA', 'hr-BA'];
      case 'EE':
        return ['et-EE'];
      case 'LV':
        return ['lv-LV'];

      // Américas
      case 'US':
        return ['en-US', 'es-US'];
      case 'CA':
        return ['en-CA', 'fr-CA'];
      case 'MX':
        return ['es-MX'];
      case 'CU':
        return ['es-CU'];
      case 'DO':
        return ['es-DO'];
      case 'PR':
        return ['es-PR', 'en-PR'];
      case 'CR':
        return ['es-CR'];
      case 'PA':
        return ['es-PA'];
      case 'GT':
        return ['es-GT'];
      case 'HN':
        return ['es-HN'];
      case 'SV':
        return ['es-SV'];
      case 'NI':
        return ['es-NI'];
      case 'CO':
        return ['es-CO'];
      case 'VE':
        return ['es-VE'];
      case 'EC':
        return ['es-EC'];
      case 'PE':
        return ['es-PE'];
      case 'BO':
        return ['es-BO'];
      case 'CL':
        return ['es-CL'];
      case 'AR':
        return ['es-AR'];
      case 'BR':
        return ['pt-BR'];
      case 'PY':
        return ['es-PY', 'gn-PY'];
      case 'UY':
        return ['es-UY'];
      case 'HT':
        return ['fr-HT', 'ht-HT'];
      case 'JM':
        return ['en-JM'];

      // África
      case 'MA':
        return ['ar-MA', 'fr-MA'];
      case 'DZ':
        return ['ar-DZ', 'fr-DZ'];
      case 'TN':
        return ['ar-TN', 'fr-TN'];
      case 'EG':
        return ['ar-EG'];
      case 'SD':
        return ['ar-SD'];
      case 'LY':
        return ['ar-LY'];
      case 'SN':
        return ['fr-SN'];
      case 'GM':
        return ['en-GM'];
      case 'GH':
        return ['en-GH'];
      case 'NG':
        return ['en-NG'];
      case 'ET':
        return ['am-ET'];
      case 'KE':
        return ['en-KE', 'sw-KE'];
      case 'TZ':
        return ['sw-TZ', 'en-TZ'];
      case 'UG':
        return ['en-UG', 'sw-UG'];
      case 'CD':
        return ['fr-CD', 'ln-CD'];
      case 'AO':
        return ['pt-AO'];
      case 'MZ':
        return ['pt-MZ'];
      case 'MG':
        return ['mg-MG', 'fr-MG'];
      case 'ZA':
        return ['en-ZA', 'af-ZA', 'zu-ZA'];
      case 'GQ':
        return ['es-GQ', 'fr-GQ', 'pt-GQ'];

      // Asia
      case 'CN':
        return ['zh-CN'];
      case 'JP':
        return ['ja-JP'];
      case 'KR':
        return ['ko-KR'];
      case 'KP':
        return ['ko-KP'];
      case 'IN':
        return ['hi-IN', 'en-IN'];
      case 'PK':
        return ['ur-PK', 'en-PK'];
      case 'NP':
        return ['ne-NP'];
      case 'LK':
        return ['si-LK', 'ta-LK'];
      case 'TH':
        return ['th-TH'];
      case 'VN':
        return ['vi-VN'];
      case 'KH':
        return ['km-KH'];
      case 'LA':
        return ['lo-LA'];
      case 'MM':
        return ['my-MM'];
      case 'MY':
        return ['ms-MY'];
      case 'SG':
        return ['en-SG', 'zh-SG', 'ms-SG', 'ta-SG'];
      case 'ID':
        return ['id-ID'];
      case 'PH':
        return ['fil-PH', 'en-PH'];
      case 'IL':
        return ['he-IL', 'ar-IL'];

      // Oceanía
      case 'AU':
        return ['en-AU'];
      case 'NZ':
        return ['en-NZ', 'mi-NZ'];
      case 'FJ':
        return ['en-FJ', 'fj-FJ'];

      // Por defecto: devolver vacío para indicar que no hay mapeo conocido
      default:
        return <String>[];
    }
  }
}
