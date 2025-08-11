import 'package:ai_chan/constants/countries_es.dart';

class LocaleUtils {
  // Nombre del país en español (simplificado)
  static String countryNameEs(String? iso2, {String fallback = 'tu país'}) {
    if (iso2 == null || iso2.trim().isEmpty) return fallback;
    return CountriesEs.codeToName[iso2.toUpperCase()] ?? fallback;
  }

  // Idioma principal del país (en español)
  static String languageNameEsForCountry(String? iso2, {String fallback = 'Español'}) {
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
  static String languagesListForPair({String? aiCountryCode, String? userCountryCode}) {
    final Set<String> langs = {};
    final aiLang = languageNameEsForCountry(aiCountryCode);
    final userLang = languageNameEsForCountry(userCountryCode);
    langs.add(aiLang);
    langs.add(userLang);
    // Inglés como comodín global
    langs.add('Inglés');
    return langs.join(', ');
  }

  // Devuelve la lista de países (nombre → iso2) para construir dropdowns
  static List<CountryItem> countriesEsList() => CountriesEs.items;

  // Convierte un código ISO2 en emoji de bandera (usa indicadores regionales Unicode)
  static String flagEmojiForCountry(String? iso2) {
    if (iso2 == null || iso2.length != 2) return '';
    final code = iso2.toUpperCase();
    int base = 0x1F1E6; // Regional Indicator Symbol Letter A
    int aCode = 'A'.codeUnitAt(0);
    final int first = base + (code.codeUnitAt(0) - aCode);
    final int second = base + (code.codeUnitAt(1) - aCode);
    return String.fromCharCode(first) + String.fromCharCode(second);
  }
}
