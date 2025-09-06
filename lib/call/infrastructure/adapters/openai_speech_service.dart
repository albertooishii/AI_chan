import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ai_chan/shared/constants/openai_voices.dart';
import 'package:ai_chan/core/config.dart';

class OpenAISpeechService {
  static void _maybeDebugPrint(final String msg) {
    if (!kDebugMode) return;
    debugPrint('[OpenAI TTS] $msg');
  }

  // Marca para evitar reintentos cuando el endpoint remoto no existe (404).
  // Se puede forzar reintento pasando `forceRefresh: true`.
  static bool _remoteVoicesUnavailable = false;

  /// Devuelve una lista de voces usando la lista oficial estática del proyecto
  /// (definida en `kOpenAIVoices`) por defecto. Si hay una API key disponible
  /// en `Config.getOpenAIKey()` intentará pedir la lista a
  /// `https://api.openai.com/v1/audio/voices` y mapearla al formato esperado.
  /// Conserva `forceRefresh` para compatibilidad. Si `femaleOnly` es true,
  /// devuelve sólo las voces listadas en `kOpenAIFemaleVoices`.
  static Future<List<Map<String, dynamic>>> fetchOpenAIVoices({
    final bool forceRefresh = false,
    final bool femaleOnly = false,
  }) async {
    _maybeDebugPrint(
      'fetchOpenAIVoices - start (forceRefresh=$forceRefresh, femaleOnly=$femaleOnly)',
    );

    final apiKey = Config.getOpenAIKey();

    // Si previamente detectamos que el endpoint remoto no existe, evitamos
    // volver a intentar, salvo cuando el llamador fuerza un refresh.
    if (apiKey.isNotEmpty && (!_remoteVoicesUnavailable || forceRefresh)) {
      try {
        _maybeDebugPrint('Attempting remote fetch from /v1/audio/voices');
        final resp = await http
            .get(
              Uri.parse('https://api.openai.com/v1/audio/voices'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          final body = json.decode(resp.body);
          if (body is Map && body['data'] is List) {
            final remote = (body['data'] as List).map<Map<String, dynamic>>((
              final item,
            ) {
              if (item is Map) {
                return {
                  'name': item['name'] ?? item['id'] ?? 'unknown',
                  'description': item['description'] ?? item['name'] ?? '',
                  'gender': (item['gender'] ?? 'unknown').toString(),
                  'languageCodes': (item['language_codes'] is List)
                      ? List<String>.from(
                          item['language_codes'].map((final e) => e.toString()),
                        )
                      : <String>[],
                };
              }
              return {
                'name': item.toString(),
                'description': item.toString(),
                'gender': 'unknown',
                'languageCodes': <String>[],
              };
            }).toList();

            _maybeDebugPrint('Remote fetch succeeded: ${remote.length} voices');
            final filtered = femaleOnly
                ? remote
                      .where(
                        (final v) =>
                            (v['gender'] as String).toLowerCase() == 'female',
                      )
                      .toList()
                : remote;
            return Future.value(filtered);
          }

          _maybeDebugPrint(
            'Remote response format unexpected, falling back to static list',
          );
        } else {
          _maybeDebugPrint(
            'Remote fetch failed: status=${resp.statusCode} body=${resp.body}',
          );
          // Si el endpoint no existe, marcamos como no disponible para evitar
          // reintentos continuos. Se puede forzar reintento con forceRefresh.
          if (resp.statusCode == 404) {
            _remoteVoicesUnavailable = true;
            _maybeDebugPrint(
              'Remote voices endpoint returned 404; disabling remote fetch until forceRefresh=true',
            );
          }
        }
      } on Exception catch (e, st) {
        _maybeDebugPrint('Remote fetch error: $e\n$st');
      }
    } else if (apiKey.isNotEmpty && _remoteVoicesUnavailable) {
      _maybeDebugPrint(
        'Skipping remote fetch because endpoint was previously detected as unavailable (pass forceRefresh=true to retry)',
      );
    } else {
      _maybeDebugPrint('No OPENAI API key available, using static voice list');
    }

    // Fallback local static list derived from the voice gender map
    final all = kOpenAIVoices.map((final name) {
      final genderLabel = kOpenAIVoiceGender[name];
      final isFemale =
          (genderLabel != null && genderLabel.toLowerCase().contains('femen'));
      return {
        'name': name,
        'description': name,
        'gender': isFemale ? 'female' : 'unknown',
        'languageCodes': <String>[],
      };
    }).toList();

    if (femaleOnly) {
      return Future.value(
        all
            .where(
              (final v) => (v['gender'] as String).toLowerCase() == 'female',
            )
            .toList(),
      );
    }

    return Future.value(all);
  }
}
