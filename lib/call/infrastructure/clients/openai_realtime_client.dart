import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';

import '../../../core/interfaces/i_realtime_client.dart';
import '../transport/openai_transport.dart';

class OpenAIRealtimeClient implements IRealtimeClient {
  final String model;
  final void Function(String textDelta)? onText;
  final void Function(Uint8List audioChunk)? onAudio;
  final void Function()? onCompleted;
  final void Function(Object err)? onError;
  final void Function(String userTranscription)? onUserTranscription;

  late final OpenAITransport _transport;
  Completer<void>? _sessionReadyCompleter;

  OpenAIRealtimeClient({
    String? model,
    this.onText,
    this.onAudio,
    this.onCompleted,
    this.onError,
    this.onUserTranscription,
  }) : model = model ?? Config.requireOpenAIRealtimeModel() {
    _transport = OpenAITransport(model: model);
    _transport.onMessage = _onTransportMessage;
    _transport.onError = (e) => onError?.call(e);
    _transport.onDone = () => onCompleted?.call();
  }
  // Nota: OpenAI realtime debe usar el OPENAI_REALTIME_MODEL configurado; fallar si no está presente.

  String get _apiKey => Config.getOpenAIKey();
  @override
  bool get isConnected => _transport.isConnected;
  int _bytesSinceCommit = 0;
  bool _hasAppendedSinceConnect = false;
  DateTime? _lastAppendAt;
  bool _commitScheduled = false;
  bool _serverTurnDetection = false;
  bool _hasActiveResponse = false;
  Timer? _responseCreateTimer;
  String _voice = 'marin'; // se ajustará en connect()
  // Versión simple sin interceptores ni guardias

  @override
  Future<void> connect({
    required String systemPrompt,
    String? inputAudioFormat,
    String? outputAudioFormat,
    String voice = 'marin', // el controlador ya normaliza antes de llamar
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    // Provide defaults for compatibility
    inputAudioFormat ??= 'pcm16';
    outputAudioFormat ??= 'pcm16';
    turnDetectionType ??= 'server_vad';
    silenceDurationMs ??= 700;
    if (_apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI.');
    }
    if (kDebugMode) debugPrint('Realtime: conectando con modelo=$model');
    await _transport.connect(options: options ?? {});
    _bytesSinceCommit = 0;
    _hasAppendedSinceConnect = false;
    _serverTurnDetection =
        (turnDetectionType == 'server_vad' ||
        turnDetectionType == 'semantic_vad');
    _voice = voice;
    final sessionReady = Completer<void>(); // session.created
    _sessionReadyCompleter = sessionReady;
    // Transport will push messages to _onTransportMessage via the transport's onMessage.

    // Esperar a que la sesión esté creada
    try {
      await sessionReady.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Realtime: timeout esperando session.created');
      }
    } finally {
      _sessionReadyCompleter = null;
    }
    // No esperar session.updated en versión simple
  }

  void _onTransportMessage(Object message) {
    try {
      if (message is Map) {
        _processEvent(message);
      } else if (message is String) {
        final dec = jsonDecode(message);
        if (dec is Map) _processEvent(dec);
      } else if (message is List<int>) {
        onAudio?.call(Uint8List.fromList(message));
      }
    } catch (e) {
      onError?.call(e);
    }
  }

  void _processEvent(Map evt) {
    final type = (evt['type'] ?? '').toString();
    bool handledAudio = false;
    bool handledText = false;

    // session.created -> send session.update and complete session completer
    if (type == 'session.created') {
      if (kDebugMode) {
        Log.d('Realtime: session.created recibido, aplicando voice="$_voice"');
      }
      _transport.sendEvent({
        'type': 'session.update',
        'session': {
          'instructions': '',
          'modalities': ['audio', 'text'],
          'input_audio_format': 'pcm16',
          'output_audio_format': 'pcm16',
          'input_audio_transcription': {
            'model': Config.getOpenAISttModel(),
            'language': 'es',
          },
          'voice': _voice,
          // Optimización para gpt-realtime: mejor detección de turnos
          'turn_detection': {
            'type': 'server_vad',
            'threshold': 0.5,
            'prefix_padding_ms': 300,
            'silence_duration_ms': 700,
          },
          // Configuración de temperatura para respuestas más naturales
          'temperature': 0.8,
          'max_response_output_tokens': 4096,
        },
      });
      try {
        _sessionReadyCompleter?.complete();
      } catch (_) {}
      return;
    }

    if (kDebugMode) {
      final noisy =
          type.startsWith('response.audio_transcript.') ||
          type == 'response.audio.delta';
      if (!noisy) Log.d('Realtime IN: type=$type');
      if (type == 'response.created') {
        final mods = (evt['response'] is Map)
            ? (evt['response']['modalities'])
            : null;
        Log.d('Realtime IN: response.created modalities=${mods ?? 'unknown'}');
      }
    }

    if (type == 'response.created' || type == 'response.output_item.added') {
      _hasActiveResponse = true;
      _responseCreateTimer?.cancel();
      _responseCreateTimer = null;
    }

    // Transcriptions
    if (type.startsWith('response.audio_transcript.') &&
        evt['delta'] is String) {
      final tx = (evt['delta'] as String).trim();
      if (tx.isNotEmpty) onText?.call(tx);
    }
    if (type == 'response.audio_transcript.done') {
      final t = (evt['transcript'] ?? '').toString();
      if (t.isNotEmpty) onText?.call(t);
    }

    // Shallow delta handling
    final delta = evt['delta'];
    if (delta is Map) {
      final dType = (delta['type'] ?? '').toString();
      if ((dType.contains('output_text') || dType.contains('text')) &&
          delta['text'] is String) {
        onText?.call(delta['text']);
        handledText = true;
      }
      final isAudioEvent = type.startsWith('response.audio.');
      if ((isAudioEvent || dType.contains('output_audio')) &&
          delta['audio'] is String) {
        try {
          final bytes = base64Decode(delta['audio']);
          onAudio?.call(bytes);
          handledAudio = true;
        } catch (e) {
          onError?.call(e);
        }
      }
    } else if (delta is String) {
      if (type.contains('output_text') || type.contains('text')) {
        onText?.call(delta);
        handledText = true;
      }
      if (type.startsWith('response.audio.')) {
        try {
          final bytes = base64Decode(delta);
          onAudio?.call(bytes);
          handledAudio = true;
        } catch (e) {
          onError?.call(e);
        }
      }
    }

    // Top-level output/content arrays
    final output = evt['output'] ?? evt['content'];
    if (output is List) {
      for (final part in output) {
        if (part is Map) {
          final pType = (part['type'] ?? '').toString();
          if ((pType.contains('output_text') || pType.contains('text')) &&
              part['text'] is String) {
            if (!handledText) onText?.call(part['text']);
            handledText = true;
          }
          if ((pType.contains('output_audio') || pType.contains('audio')) &&
              part['audio'] is String) {
            try {
              if (!handledAudio) {
                final bytes = base64Decode(part['audio']);
                onAudio?.call(bytes);
                handledAudio = true;
              }
            } catch (e) {
              onError?.call(e);
            }
          }
        }
      }
    }

    // Deep response parsing using existing extractor
    final resp = evt['response'];
    if (resp is Map) {
      _extractAndEmitFromResponse(resp);
      final rOutput = resp['output'];
      if (rOutput is List) {
        for (final part in rOutput) {
          if (part is Map) {
            final pType = (part['type'] ?? '').toString();
            if ((pType.contains('output_text') || pType.contains('text')) &&
                part['text'] is String) {
              if (!handledText) onText?.call(part['text']);
              handledText = true;
            }
            if (part['content'] is List) {
              for (final c in (part['content'] as List)) {
                if (c is Map) {
                  final ct = (c['type'] ?? '').toString();
                  if ((ct.contains('output_text') || ct.contains('text')) &&
                      c['text'] is String) {
                    if (!handledText) onText?.call(c['text']);
                    handledText = true;
                  }
                  if ((ct.contains('output_audio') || ct.contains('audio')) &&
                      c['audio'] is String) {
                    try {
                      if (!handledAudio) {
                        final bytes = base64Decode(c['audio']);
                        onAudio?.call(bytes);
                        handledAudio = true;
                      }
                    } catch (e) {
                      onError?.call(e);
                    }
                  }
                }
              }
            }
            if ((pType.contains('output_audio') || pType.contains('audio')) &&
                part['audio'] is String) {
              try {
                if (!handledAudio) {
                  final bytes = base64Decode(part['audio']);
                  onAudio?.call(bytes);
                  handledAudio = true;
                }
              } catch (e) {
                onError?.call(e);
              }
            }
          }
        }
      }
      final rContent = resp['content'];
      if (rContent is List) {
        for (final c in rContent) {
          if (c is Map) {
            final ct = (c['type'] ?? '').toString();
            if ((ct.contains('output_text') || ct.contains('text')) &&
                c['text'] is String) {
              onText?.call(c['text']);
            }
            if ((ct.contains('output_audio') || ct.contains('audio')) &&
                c['audio'] is String) {
              try {
                final bytes = base64Decode(c['audio']);
                onAudio?.call(bytes);
              } catch (e) {
                onError?.call(e);
              }
            }
          }
        }
      }
    }

    // Audio delta variants if not yet handled
    if (type.startsWith('response.audio.') && !handledAudio) {
      String? b64;
      if (evt['audio'] is String) b64 = evt['audio'];
      if (b64 == null &&
          evt['delta'] is Map &&
          evt['delta']['audio'] is String) {
        b64 = evt['delta']['audio'];
      }
      if (b64 == null && evt['delta'] is String) {
        b64 = evt['delta'];
      }
      if (b64 != null) {
        try {
          final bytes = base64Decode(b64);
          onAudio?.call(bytes);
          handledAudio = true;
        } catch (e) {
          onError?.call(e);
        }
      }
    }

    // response.done / completed -> completion and error mapping
    if (type == 'response.done' || type == 'response.completed') {
      onCompleted?.call();
      final resp2 = evt['response'];
      if (resp2 is Map) {
        final status = (resp2['status'] ?? '').toString();
        if (status == 'failed') {
          final err = (resp2['status_details'] is Map)
              ? resp2['status_details']['error']
              : null;
          final code = (err is Map) ? (err['code'] ?? '').toString() : '';
          final msg = (err is Map) ? (err['message'] ?? '').toString() : '';
          if (kDebugMode) debugPrint('Realtime response failed: $code $msg');
          onError?.call(Exception('response_failed:$code $msg'));
        }
      }
      _hasActiveResponse = false;
    }

    // Server VAD / input committed handling
    if (type == 'input_audio_buffer.committed' && _serverTurnDetection) {
      if (!_hasActiveResponse) requestResponse();
    }
    if (!_serverTurnDetection &&
        (type == 'input_audio_buffer.committed' ||
            type == 'input_audio_buffer.speech_stopped')) {
      requestResponse();
    }

    // User transcription - Mejorado para gpt-realtime
    if (type == 'conversation.item.input_audio_transcription.completed') {
      final transcript = (evt['transcript'] ?? '').toString().trim();
      if (transcript.isNotEmpty) {
        onUserTranscription?.call(transcript);
      } else {
        final altTranscript = (evt['text'] ?? evt['content'] ?? '')
            .toString()
            .trim();
        if (altTranscript.isNotEmpty) onUserTranscription?.call(altTranscript);
      }
    }

    // Manejo de errores mejorado para gpt-realtime
    if (type == 'error' && evt['error'] != null) {
      final error = evt['error'];
      String errorMsg = 'Error desconocido';

      if (error is Map) {
        final code = error['code']?.toString() ?? '';
        final message = error['message']?.toString() ?? '';
        final errorType = error['type']?.toString() ?? '';

        errorMsg = 'Error $errorType ($code): $message';

        // Manejar errores específicos del modelo gpt-realtime
        if (code.contains('insufficient_quota')) {
          errorMsg = 'Cuota agotada. Verifica tu plan de OpenAI.';
        } else if (code.contains('model_not_found')) {
          errorMsg =
              'Modelo gpt-realtime no disponible. Verifica tu suscripción.';
        } else if (code.contains('invalid_request_error')) {
          errorMsg = 'Configuración de sesión inválida: $message';
        } else if (code.contains('authentication_error')) {
          errorMsg = 'Error de autenticación. Verifica tu API key.';
        }
      } else {
        errorMsg = error.toString();
      }

      if (kDebugMode) {
        Log.w('Realtime error: $errorMsg', tag: 'OPENAI_REALTIME');
      }
      onError?.call(Exception(errorMsg));
    }

    // Nuevos eventos para gpt-realtime: session.updated
    if (type == 'session.updated') {
      if (kDebugMode) {
        final voice = evt['session']?['voice']?.toString() ?? 'unknown';
        Log.d('Realtime: session.updated voice=$voice');
      }
    }

    // Manejo de interrupciones mejorado
    if (type == 'input_audio_buffer.speech_started') {
      if (kDebugMode) {
        Log.d('Realtime: speech_started - usuario comenzó a hablar');
      }
    }

    if (type == 'input_audio_buffer.speech_stopped') {
      if (kDebugMode) {
        Log.d('Realtime: speech_stopped - usuario dejó de hablar');
      }
    }
  }

  // Actualiza la voz de la sesión en caliente
  @override
  void updateVoice(String voice) {
    if (!isConnected) return;
    _send({
      'type': 'session.update',
      'session': {'voice': voice},
    });
  }

  @override
  void sendText(String text) {
    if (!isConnected) return;
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text},
        ],
      },
    });
  }

  /// Envía una imagen junto con texto opcional (nueva funcionalidad gpt-realtime)
  @override
  void sendImageWithText({
    required String imageBase64,
    String? text,
    String imageFormat = 'png',
  }) {
    if (!isConnected) return;

    final content = <Map<String, dynamic>>[];

    // Agregar imagen
    content.add({
      'type': 'input_image',
      'image_url': 'data:image/$imageFormat;base64,$imageBase64',
    });

    // Agregar texto opcional
    if (text != null && text.trim().isNotEmpty) {
      content.add({'type': 'input_text', 'text': text});
    }

    _send({
      'type': 'conversation.item.create',
      'item': {'type': 'message', 'role': 'user', 'content': content},
    });

    if (kDebugMode) {
      Log.d(
        'Realtime: imagen enviada (${imageBase64.length} bytes, formato: $imageFormat)',
      );
    }
  }

  /// Configura herramientas/funciones para el modelo (nueva funcionalidad mejorada)
  @override
  void configureTools(List<Map<String, dynamic>> tools) {
    if (!isConnected) return;

    _send({
      'type': 'session.update',
      'session': {'tools': tools},
    });

    if (kDebugMode) {
      Log.d('Realtime: ${tools.length} herramientas configuradas');
    }
  }

  /// Responde a una llamada de función (function calling mejorado en gpt-realtime)
  @override
  void sendFunctionCallOutput({
    required String callId,
    required String output,
  }) {
    if (!isConnected) return;

    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': output,
      },
    });

    if (kDebugMode) {
      Log.d('Realtime: respuesta de función enviada (callId: $callId)');
    }
  }

  @override
  void appendAudio(List<int> bytes) {
    if (!isConnected) return;
    _send({'type': 'input_audio_buffer.append', 'audio': base64Encode(bytes)});
    _bytesSinceCommit += bytes.length;
    _hasAppendedSinceConnect = true;
    _lastAppendAt = DateTime.now();
  }

  void commitInput() {
    if (!isConnected) return;
    if (_serverTurnDetection) {
      if (kDebugMode) {
        debugPrint('Realtime: commit manual ignorado (server VAD activo)');
      }
      return;
    }
    // Evitar commit vacío: exigir >= ~100ms de PCM16 mono @16kHz (~3200 bytes)
    if (!_hasAppendedSinceConnect || _bytesSinceCommit < 3200) {
      if (kDebugMode) {
        debugPrint(
          'Realtime: evitando commit vacío (_hasAppended=$_hasAppendedSinceConnect, bytes=$_bytesSinceCommit)',
        );
      }
      return;
    }
    // Debounce: esperar a que el servidor procese los append (>=120ms desde el último append)
    final now = DateTime.now();
    final sinceMs = _lastAppendAt == null
        ? 9999
        : now.difference(_lastAppendAt!).inMilliseconds;
    if (sinceMs < 120) {
      if (_commitScheduled) return;
      final waitMs = 120 - sinceMs;
      _commitScheduled = true;
      Future.delayed(Duration(milliseconds: waitMs), () {
        if (!isConnected) return;
        if (_bytesSinceCommit < 3200) {
          if (kDebugMode) {
            debugPrint(
              'Realtime: commit diferido cancelado por bytes insuficientes ($_bytesSinceCommit)',
            );
          }
          _commitScheduled = false;
          return;
        }
        if (kDebugMode) {
          debugPrint(
            'Realtime OUT (deferred): input_audio_buffer.commit bytes=$_bytesSinceCommit',
          );
        }
        _transport.commitAudio();
        _bytesSinceCommit = 0;
        _commitScheduled = false;
      });
      return;
    }
    if (kDebugMode) {
      debugPrint(
        'Realtime OUT: input_audio_buffer.commit bytes=$_bytesSinceCommit',
      );
    }
    _transport.commitAudio();
    _bytesSinceCommit = 0;
  }

  /// Adapter for IRealtimeClient: map commitPendingAudio to commitInput
  @override
  Future<void> commitPendingAudio() async {
    // commitInput is synchronous; wrap for interface compatibility
    try {
      commitInput();
    } catch (e) {
      rethrow;
    }
  }

  // Exponer si hay audio suficiente pendiente para commit
  bool hasPendingAudio({int minBytes = 3200}) {
    return _bytesSinceCommit >= minBytes;
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    if (!isConnected) return;
    if (_hasActiveResponse) {
      if (kDebugMode) {
        debugPrint('Realtime: omitiendo response.create (ya hay activa)');
      }
      return;
    }
    final modalities = <String>[];
    if (audio) modalities.add('audio');
    if (text) modalities.add('text');
    // Pequeño delay para evitar carrera justo tras el commit
    _responseCreateTimer?.cancel();
    _responseCreateTimer = Timer(const Duration(milliseconds: 60), () {
      if (!isConnected) return;
      if (_hasActiveResponse) {
        if (kDebugMode) {
          debugPrint(
            'Realtime: cancelado response.create (respuesta activa detectada)',
          );
        }
        return;
      }
      // Si se solicita solo texto en la fase inicial, enviar además un mensaje corto
      // tipo 'usuario: llamada entrante' para forzar al modelo a emitir la etiqueta.
      if (text && !audio) {
        final incoming = {
          'type': 'conversation.item.create',
          'item': {
            'type': 'message',
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text':
                    'El usuario ha iniciado una llamada. Responde SOLO con "[start_call][/start_call]" para aceptar o "[end_call][/end_call]" para rechazar.',
              },
            ],
          },
        };
        _transport.sendEvent(incoming);
      }
      _transport.sendEvent({
        'type': 'response.create',
        'response': {'modalities': modalities},
      });
      _responseCreateTimer = null;
    });
  }

  /// Cancela la respuesta actual con mejor control para gpt-realtime
  @override
  void cancelResponse({String? itemId, int? sampleCount}) {
    if (!isConnected) return;

    final cancelEvent = <String, dynamic>{'type': 'response.cancel'};

    // Para gpt-realtime, podemos especificar qué ítem cancelar y dónde truncar
    if (itemId != null) {
      cancelEvent['item_id'] = itemId;
    }

    if (sampleCount != null) {
      cancelEvent['sample_count'] = sampleCount;
    }

    _transport.sendEvent(cancelEvent);
    _hasActiveResponse = false;

    if (kDebugMode) {
      Log.d(
        'Realtime: response.cancel enviado (itemId=$itemId, sampleCount=$sampleCount)',
      );
    }
  }

  /// Método de conveniencia para cancelación básica (mantiene compatibilidad)
  void cancelCurrentResponse() => cancelResponse();

  @override
  Future<void> close() async {
    if (isConnected) {
      try {
        _responseCreateTimer?.cancel();
        _responseCreateTimer = null;
        await _transport.disconnect();
      } catch (_) {}
    }
  }

  void _send(Map<String, dynamic> event) {
    if (!isConnected) return;
    if (kDebugMode) {
      final t = event['type'];
      if (t != 'input_audio_buffer.append') {
        debugPrint('Realtime OUT: type=$t');
      }
    }
    _transport.sendEvent(event);
  }
}

// Utilidades de parseo profundo
extension _RespExtract on OpenAIRealtimeClient {
  void _extractAndEmitFromResponse(Map resp) {
    final texts = <String>[];
    final audioChunks = <Uint8List>[];

    void scan(dynamic node) {
      if (node is Map) {
        // Texto
        final t = node['text'];
        if (t is String && t.isNotEmpty) texts.add(t);
        // Texto en 'value' cuando type incluye 'text'
        final nType = (node['type'] ?? '').toString();
        final v = node['value'];
        if (nType.contains('text') && v is String && v.isNotEmpty) {
          texts.add(v);
        }
        // Audio
        final a = node['audio'];
        if (a is String && a.isNotEmpty) {
          try {
            audioChunks.add(base64Decode(a));
          } catch (_) {}
        }
        // Audio en 'data' cuando type incluye 'audio'
        final d = node['data'];
        if (nType.contains('audio') && d is String && d.isNotEmpty) {
          try {
            audioChunks.add(base64Decode(d));
          } catch (_) {}
        }
        // Recorrer hijos
        for (final v in node.values) {
          scan(v);
        }
      } else if (node is List) {
        for (final e in node) {
          scan(e);
        }
      }
    }

    scan(resp);
    if (kDebugMode) {
      debugPrint(
        'Realtime: resp extract -> texts=${texts.length}, audioChunks=${audioChunks.length}',
      );
    }
    for (final s in texts) {
      onText?.call(s);
    }
    for (final ch in audioChunks) {
      onAudio?.call(ch);
    }
  }
}
