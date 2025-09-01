import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ai_chan/shared/utils/string_utils.dart';

/// Efecto inspirado en "traducción" de Cyberpunk 2077:
/// Cada vez que llega texto nuevo, los caracteres nuevos pasan por
/// una fase de "glitch/scramble" antes de fijarse en su valor final.
/// Además, caracteres eliminados se desvanecen con un pequeño colapso.
class CyberpunkRealtimeSubtitle extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration scramblePerChar; // duración de scramble por caracter
  final Duration
  removalDuration; // duración para desvanecer caracteres eliminados
  final bool enabled;
  final double
  glitchProbability; // probabilidad de aplicar leve tint/flicker a un char activo
  final bool useKatakana; // usar set katakana para fase de glitch

  const CyberpunkRealtimeSubtitle({
    super.key,
    required this.text,
    required this.style,
    this.scramblePerChar = const Duration(
      milliseconds: 140,
    ), // más rápido para sincronizar audio
    this.removalDuration = const Duration(milliseconds: 200),
    this.enabled = true,
    this.glitchProbability = 0.22,
    this.useKatakana = true,
  });

  @override
  State<CyberpunkRealtimeSubtitle> createState() =>
      _CyberpunkRealtimeSubtitleState();
}

class _CharAnim {
  String target; // carácter final
  String current; // carácter mostrado actual
  DateTime start; // inicio de animación (scramble) o de removido
  bool locked; // ya fijado en target
  bool removing; // en proceso de desaparecer
  double removalProgress; // 0..1
  _CharAnim({
    required this.target,
    required this.current,
    required this.start,
    this.locked = false,
  }) : removing = false,
       removalProgress = 0.0;
}

class _CyberpunkRealtimeSubtitleState extends State<CyberpunkRealtimeSubtitle>
    with SingleTickerProviderStateMixin {
  // Conjuntos para efecto de traducción (katakana → español)
  static const String _katakana =
      'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワガギグゲゴザジズゼゾダヂヅデドパピプペポバビブベボャュョッー';
  // Mapeo silábico / transliteración aproximada español -> katakana.
  // Ampliado para reducir al mínimo el uso de fallback aleatorio.
  static const Map<String, String> _syllableToKana = {
    // Vocales
    'a': 'ア', 'e': 'エ', 'i': 'イ', 'o': 'オ', 'u': 'ウ',
    'á': 'ア', 'é': 'エ', 'í': 'イ', 'ó': 'オ', 'ú': 'ウ',
    // K / C / Q / G combinaciones
    'ka': 'カ', 'ki': 'キ', 'ku': 'ク', 'ke': 'ケ', 'ko': 'コ',
    'ca': 'カ',
    'co': 'コ',
    'cu': 'ク',
    'que': 'ケ',
    'qui': 'キ',
    'qua': 'クア',
    'quo': 'クオ',
    'gua': 'グア', 'güe': 'グエ', 'güi': 'グイ',
    'ga': 'ガ', 'gu': 'グ', 'gue': 'ゲ', 'gui': 'ギ', 'go': 'ゴ',
    // S / Z / C(e/i)
    'sa': 'サ', 'se': 'セ', 'si': 'シ', 'so': 'ソ', 'su': 'ス',
    'za': 'ザ', 'ze': 'ゼ', 'zi': 'ジ', 'zo': 'ゾ', 'zu': 'ズ',
    'ce': 'セ', 'ci': 'シ',
    // T / D
    'ta': 'タ', 'te': 'テ', 'ti': 'ティ', 'to': 'ト', 'tu': 'トゥ',
    'da': 'ダ', 'de': 'デ', 'di': 'ディ', 'do': 'ド', 'du': 'ドゥ',
    // N
    'na': 'ナ', 'ne': 'ネ', 'ni': 'ニ', 'no': 'ノ', 'nu': 'ヌ',
    // P / B
    'pa': 'パ', 'pe': 'ペ', 'pi': 'ピ', 'po': 'ポ', 'pu': 'プ',
    'ba': 'バ', 'be': 'ベ', 'bi': 'ビ', 'bo': 'ボ', 'bu': 'ブ',
    // M
    'ma': 'マ', 'me': 'メ', 'mi': 'ミ', 'mo': 'モ', 'mu': 'ム',
    // L / R + grupos con l / r
    'la': 'ラ', 'le': 'レ', 'li': 'リ', 'lo': 'ロ', 'lu': 'ル',
    'ra': 'ラ', 're': 'レ', 'ri': 'リ', 'ro': 'ロ', 'ru': 'ル',
    'pla': 'プラ', 'ple': 'プレ', 'pli': 'プリ', 'plo': 'プロ', 'plu': 'プル',
    'pra': 'プラ', 'pre': 'プレ', 'pri': 'プリ', 'pro': 'プロ', 'pru': 'プル',
    'bla': 'ブラ', 'ble': 'ブレ', 'bli': 'ブリ', 'blo': 'ブロ', 'blu': 'ブル',
    'bra': 'ブラ', 'bre': 'ブレ', 'bri': 'ブリ', 'bro': 'ブロ', 'bru': 'ブル',
    'cla': 'クラ', 'cle': 'クレ', 'cli': 'クリ', 'clo': 'クロ', 'clu': 'クル',
    'cra': 'クラ', 'cre': 'クレ', 'cri': 'クリ', 'cro': 'クロ', 'cru': 'クル',
    'dra': 'ドラ', 'dre': 'ドレ', 'dri': 'ドリ', 'dro': 'ドロ', 'dru': 'ドル',
    'fra': 'フラ', 'fre': 'フレ', 'fri': 'フリ', 'fro': 'フロ', 'fru': 'フル',
    'fla': 'フラ', 'fle': 'フレ', 'fli': 'フリ', 'flo': 'フロ', 'flu': 'フル',
    'gla': 'グラ', 'gle': 'グレ', 'gli': 'グリ', 'glo': 'グロ', 'glu': 'グル',
    'gra': 'グラ', 'gre': 'グレ', 'gri': 'グリ', 'gro': 'グロ', 'gru': 'グル',
    'tra': 'トラ', 'tre': 'トレ', 'tri': 'トリ', 'tro': 'トロ', 'tru': 'トル',
    'tla': 'トラ', 'tle': 'トレ', 'tli': 'トリ', 'tlo': 'トロ', 'tlu': 'トル',
    // Y
    'ya': 'ヤ', 'ye': 'イェ', 'yi': 'イ', 'yo': 'ヨ', 'yu': 'ユ',
    // CH
    'cha': 'チャ', 'che': 'チェ', 'chi': 'チ', 'cho': 'チョ', 'chu': 'チュ', 'ch': 'チ',
    // LL
    'lla': 'リャ', 'lle': 'リエ', 'lli': 'リ', 'llo': 'リョ', 'llu': 'リュ', 'll': 'リ',
    // RR (representar como pequeña pausa + ra)
    'rr': 'ッラ',
    // Ñ: sílabas palatales; standalone marcada con sokuon + nasal para enfatizar (ッン)
    'ña': 'ニャ', 'ñe': 'ニェ', 'ñi': 'ニ', 'ño': 'ニョ', 'ñu': 'ニュ', 'ñ': 'ッン',
    // V / W / F (en español v ~ b, unificamos con la serie バ)
    'va': 'バ', 've': 'ベ', 'vi': 'ビ', 'vo': 'ボ', 'vu': 'ブ', 'v': 'ブ',
    'wa': 'ワ', 'we': 'ウェ', 'wi': 'ウィ', 'wo': 'ヲ', 'wu': 'ウ', 'w': 'ワ',
    'fa': 'ファ', 'fe': 'フェ', 'fi': 'フィ', 'fo': 'フォ', 'fu': 'フ',
    // Otros
    'ex': 'エクス', 'cion': 'シオン', 'ción': 'シオン', 'ció': 'シオ',
    // Consonantes/residuos finales frecuentes (evitamos fallback aleatorio)
    'n': 'ン',
    'm': 'ム',
    's': 'ス',
    'r': 'ル',
    'l': 'ル',
    'g': 'グ',
    'k': 'ク',
    't': 'ト',
    'd': 'ド',
    'p': 'プ', 'b': 'ブ', 'f': 'フ', 'x': 'クス', 'j': 'ホ', 'q': 'ク',
    // H muda (equivalente a vocal sola)
    'ha': 'ア', 'he': 'エ', 'hi': 'イ', 'ho': 'オ', 'hu': 'ウ',
    // J / G (ge, gi) español como fricativa velar -> fila ハ
    'ja': 'ハ', 'je': 'ヘ', 'ji': 'ヒ', 'jo': 'ホ', 'ju': 'フ',
    'ge': 'ヘ', 'gi': 'ヒ',
    // Gü + vocal y guo
    'güa': 'グア', 'güo': 'グオ', 'guo': 'グオ',
    // Diptongos / triptongos frecuentes (representación directa)
    'ai': 'アイ', 'ei': 'エイ', 'oi': 'オイ', 'au': 'アウ', 'eu': 'エウ',
    'ia': 'イア', 'ie': 'イエ', 'io': 'イオ', 'iu': 'イウ',
    'ua': 'ウア', 'ue': 'ウエ', 'ui': 'ウイ', 'uo': 'ウオ',
    'ay': 'アイ', 'ey': 'エイ', 'oy': 'オイ', 'uy': 'ウイ',
    // Sufijos y grupos frecuentes
    'sion': 'シオン', 'sión': 'シオン', 'tion': 'シオン', 'cción': 'クシオン',
    'mente': 'メンテ', 'ment': 'メント',
    // Préstamos ingles / internacionalismos
    'sh': 'シュ', 'ph': 'フ', 'ck': 'ク', 'ing': 'イング',
    // Conjunción / letra y
    'y': 'イ',
  };
  // Lista ordenada de patrones (longest-first) para segmentación silábica.
  static final List<String> _orderedPatterns = _syllableToKana.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  // Separadores / signos que preservamos como unidades independientes.
  static final RegExp _punctOrSpace = RegExp(r'[\s.,;:!?¡¿"()\[\]{}…-]');
  static final _rand = Random();

  late final Ticker _ticker;
  final List<_CharAnim> _chars = [];
  List<String> _lastUnits = [];
  // último texto (por ahora no utilizado externamente, se mantiene por si se amplía diff)

  @override
  void initState() {
    super.initState();
    _initChars(widget.text);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(CyberpunkRealtimeSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _applyDiff(oldWidget.text, widget.text);
    }
  }

  void _initChars(String text) {
    final units = _splitIntoUnits(text);
    _chars.clear();
    final now = DateTime.now();
    for (final u in units) {
      _chars.add(_CharAnim(target: u, current: u, start: now, locked: true));
    }
    _lastUnits = units;
  }

  void _applyDiff(String oldText, String newText) {
    final oldUnits = _lastUnits;
    final newUnits = _splitIntoUnits(newText);
    final now = DateTime.now();

    // Encontrar prefijo común en unidades
    int prefix = 0;
    final minLen = oldUnits.length < newUnits.length
        ? oldUnits.length
        : newUnits.length;
    while (prefix < minLen && oldUnits[prefix] == newUnits[prefix]) {
      prefix++;
    }

    // Marcar sobrantes (removidos)
    if (newUnits.length < oldUnits.length) {
      for (int i = newUnits.length; i < _chars.length; i++) {
        final ch = _chars[i];
        if (!ch.removing) {
          ch.removing = true;
          ch.start = now;
        }
      }
    }

    final updated = <_CharAnim>[];
    for (int i = 0; i < newUnits.length; i++) {
      final target = newUnits[i];
      if (i < _chars.length) {
        final existing = _chars[i];
        if (i < prefix) {
          existing
            ..target = target
            ..current = target
            ..locked = true
            ..removing = false
            ..removalProgress = 0.0;
          updated.add(existing);
        } else if (existing.target != target) {
          updated.add(
            _CharAnim(
              target: target,
              current: _randomScrambleChar(
                replaceWith: target,
                useKatakana: widget.useKatakana,
              ),
              start: now,
            ),
          );
        } else {
          existing
            ..locked = true
            ..removing = false
            ..removalProgress = 0.0
            ..current = target;
          updated.add(existing);
        }
      } else {
        updated.add(
          _CharAnim(
            target: target,
            current: _randomScrambleChar(
              replaceWith: target,
              useKatakana: widget.useKatakana,
            ),
            start: now,
          ),
        );
      }
    }

    _chars
      ..clear()
      ..addAll(updated);
    _lastUnits = newUnits;
  }

  // Segmentación silábica aproximada (greedy longest-first usando patrones conocidos).
  List<String> _splitIntoUnits(String text) {
    final lower = text.toLowerCase();
    final units = <String>[];
    int i = 0;
    while (i < lower.length) {
      final ch = lower[i];
      if (_punctOrSpace.hasMatch(ch)) {
        // puntuación -> unidad individual
        units.add(text[i]);
        i++;
        continue;
      }
      String? match;
      // Greedy longest-first con normalización de acentos
      for (final pat in _orderedPatterns) {
        if (pat.length <= lower.length - i) {
          final slice = lower.substring(i, i + pat.length);
          if (slice == pat || removeAccents(slice).toLowerCase() == pat) {
            match = text.substring(i, i + pat.length);
            break;
          }
        }
      }
      // Degradar: consonante + vocal
      if (match == null && i + 1 < lower.length) {
        final pair = lower.substring(i, i + 2);
        final npair = removeAccents(pair).toLowerCase();
        if (_syllableToKana.containsKey(npair)) {
          match = text.substring(i, i + 2);
        }
      }
      // Último recurso: un carácter (que debería tener mapeo: vocal o consonante final)
      match ??= text[i];
      units.add(match);
      i += match.length;
    }
    return units;
  }

  static String _randomScrambleChar({
    String? replaceWith,
    required bool useKatakana,
  }) {
    if (replaceWith != null &&
        RegExp(r'[\s.,;:!?¡¿"()\[\]{}…-]').hasMatch(replaceWith)) {
      return replaceWith;
    }
    if (!useKatakana) return _katakana[_rand.nextInt(_katakana.length)];
    if (replaceWith != null && replaceWith.isNotEmpty) {
      final lower = replaceWith.toLowerCase();
      final norm = removeAccents(lower).toLowerCase();
      final String? mapped = _syllableToKana[lower] ?? _syllableToKana[norm];
      if (mapped == null && norm.length > 1) {
        // Descomponer greedy en sub-sílabas ya normalizadas
        final pool = <int>[];
        int i = 0;
        while (i < norm.length) {
          bool matched = false;
          for (int len = (norm.length - i).clamp(1, 4); len > 0; len--) {
            final slice = norm.substring(i, i + len);
            final m = _syllableToKana[slice];
            if (m != null) {
              pool.addAll(m.runes);
              i += len;
              matched = true;
              break;
            }
          }
          if (!matched) {
            // Carácter individual (vocal/consonante final mapeada) o fallback vocal
            final single = _syllableToKana[norm[i]] ?? 'ア';
            pool.addAll(single.runes);
            i++;
          }
        }
        if (pool.isNotEmpty) {
          return String.fromCharCode(pool[_rand.nextInt(pool.length)]);
        }
      } else if (mapped != null) {
        final chars = mapped.runes.toList();
        return String.fromCharCode(chars[_rand.nextInt(chars.length)]);
      }
    }
    // Fallback determinista controlado (vocal básica)
    const vowels = 'アイウエオ';
    return vowels[_rand.nextInt(vowels.length)];
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    bool needsSetState = false;
    for (final ch in _chars) {
      if (ch.removing) {
        final dt = now.difference(ch.start);
        final p = (dt.inMilliseconds / widget.removalDuration.inMilliseconds)
            .clamp(0.0, 1.0);
        if (p != ch.removalProgress) {
          ch.removalProgress = p;
          needsSetState = true;
        }
        continue;
      }
      if (!ch.locked) {
        final dt = now.difference(ch.start);
        if (dt >= widget.scramblePerChar) {
          ch.current = ch.target;
          ch.locked = true;
          needsSetState = true;
        } else {
          // Cambiar carácter aleatorio cada ~45ms
          if (dt.inMilliseconds % 38 < 18) {
            // ticks algo más rápidos
            final prev = ch.current;
            ch.current = _randomScrambleChar(
              replaceWith: ch.target,
              useKatakana: widget.useKatakana,
            );
            if (ch.current != prev) needsSetState = true;
          }
        }
      }
    }

    if (needsSetState && mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Text(
        widget.text,
        style: widget.style,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <InlineSpan>[];
    for (final ch in _chars) {
      final isGlitching =
          !ch.locked &&
          !ch.removing &&
          _rand.nextDouble() < widget.glitchProbability;
      final baseColor = widget.style.color!;
      Color computeAlpha(Color c, double alpha) =>
          c.withValues(alpha: (c.a * alpha));
      final color = ch.removing
          ? computeAlpha(baseColor, 1.0 - ch.removalProgress)
          : isGlitching
          ? computeAlpha(Color.lerp(baseColor, Colors.pinkAccent, 0.6)!, 0.85)
          : ch.locked
          ? baseColor
          : computeAlpha(baseColor, 0.75);
      final scale = ch.removing
          ? 1.0 - (0.2 * ch.removalProgress)
          : (isGlitching ? 1.05 : 1.0);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Transform.scale(
            scale: scale,
            child: Text(
              ch.current,
              style: widget.style.copyWith(
                color: color,
                shadows: isGlitching
                    ? [const Shadow(blurRadius: 8, color: Colors.pinkAccent)]
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    // Sin límite de líneas: el contenedor padre se encarga de scroll si es necesario.
    return RichText(
      textAlign: TextAlign.left,
      text: TextSpan(children: spans),
    );
  }
}
