import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:web_socket_channel/io.dart';

import '../../../core/interfaces/i_realtime_client.dart';

class OpenAIRealtimeClient implements IRealtimeClient {
  final String model;
  final void Function(String textDelta)? onText;
  final void Function(Uint8List audioChunk)? onAudio;
  final void Function()? onCompleted;
  final void Function(Object err)? onError;
  final void Function(String userTranscription)? onUserTranscription;

  IOWebSocketChannel? _channel;
  bool _connected = false;

  OpenAIRealtimeClient({
    String? model,
    this.onText,
    this.onAudio,
    this.onCompleted,
    this.onError,
    this.onUserTranscription,
  }) : model = model ?? Config.requireOpenAIRealtimeModel();
  // Nota: OpenAI realtime debe usar el OPENAI_REALTIME_MODEL configurado; fallar si no está presente.

  String get _apiKey => Config.getOpenAIKey();
  @override
  bool get isConnected => _connected;
  int _bytesSinceCommit = 0;
  bool _hasAppendedSinceConnect = false;
  DateTime? _lastAppendAt;
  bool _commitScheduled = false;
  bool _serverTurnDetection = false;
  bool _hasActiveResponse = false;
  Timer? _responseCreateTimer;
  String _voice = 'sage'; // se ajustará en connect()
  // Versión simple sin interceptores ni guardias

  @override
  Future<void> connect({
    required String systemPrompt,
    String? inputAudioFormat,
    String? outputAudioFormat,
    String voice = 'sage', // el controlador ya normaliza antes de llamar
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
    final uri = Uri.parse('wss://api.openai.com/v1/realtime?model=$model');
    if (kDebugMode) {
      debugPrint('Realtime: conectando con modelo=$model');
    }
    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $_apiKey', 'OpenAI-Beta': 'realtime=v1'},
    );
    _connected = true;
    _bytesSinceCommit = 0;
    _hasAppendedSinceConnect = false;
    _serverTurnDetection = (turnDetectionType == 'server_vad' || turnDetectionType == 'semantic_vad');
    _voice = voice;
    final sessionReady = Completer<void>(); // session.created
    final sessionConfigured = Completer<void>(); // session.updated tras aplicar instrucciones

    // Preparar evento de actualización de sesión (voice, modalidades, formatos, VAD)
    final sessionUpdateEvent = {
      'type': 'session.update',
      'session': {
        'instructions': systemPrompt,
        'modalities': ['audio', 'text'],
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {'model': Config.getOpenAISttModel(), 'language': 'es'},
        'voice': voice,
        'turn_detection': {
          'type': turnDetectionType,
          if (turnDetectionType == 'server_vad') 'silence_duration_ms': silenceDurationMs,
        },
      },
    };
    _channel!.stream.listen(
      (dynamic message) {
        try {
          if (message is String) {
            final evt = jsonDecode(message);
            final type = (evt['type'] ?? '').toString();
            bool handledAudio = false;
            bool handledText = false;

            // Log específico para eventos de input_audio y transcripción
            if (type.contains('input_audio') ||
                type.contains('transcription') ||
                type.contains('conversation.item.input_audio') ||
                type.startsWith('conversation.item.')) {
              if (kDebugMode) {
                Log.d('DEBUG INPUT AUDIO EVENT: $type');
                final ev = evt.toString();
                final preview = ev.length > 200 ? ev.substring(0, 200) : ev;
                Log.d('DEBUG FULL EVENT: $preview');
              }
            }
            if (kDebugMode) {
              // Suprime tipos muy ruidosos
              final noisy = type.startsWith('response.audio_transcript.') || type == 'response.audio.delta';
              if (!noisy) Log.d('Realtime IN: type=$type');
              if (type == 'response.created') {
                final mods = (evt['response'] is Map) ? (evt['response']['modalities']) : null;
                Log.d('Realtime IN: response.created modalities=${mods ?? 'unknown'}');
              }
            }
            if (type == 'response.created' || type == 'response.output_item.added') {
              _hasActiveResponse = true;
              // cancelar un response.create pendiente si ya hay uno activo
              _responseCreateTimer?.cancel();
              _responseCreateTimer = null;
              // Ignorar session.updated (flujo simple)
            }
            // Eventos de transcripción de audio (cuando el servidor envía texto de lo que está diciendo)
            if (type.startsWith('response.audio_transcript.') && evt['delta'] is String) {
              final tx = (evt['delta'] as String).trim();
              if (tx.isNotEmpty) onText?.call(tx);
            }
            if (type == 'response.audio_transcript.done') {
              final t = (evt['transcript'] ?? '').toString();
              if (t.isNotEmpty) onText?.call(t);
            }
            if (type == 'session.created' && !sessionReady.isCompleted) {
              if (kDebugMode) Log.d('Realtime: session.created recibido, aplicando voice="$_voice"');
              // Aplicar configuración de sesión ahora que la sesión existe
              _send(sessionUpdateEvent);
              sessionReady.complete();
            }
            if (type == 'session.updated' && !sessionConfigured.isCompleted) {
              // Ignorar session.updated (flujo simple)
            }
            // Texto/audio delta (compatibilidad con variantes de evento)
            final delta = evt['delta'];
            if (delta is Map) {
              final dType = (delta['type'] ?? '').toString();
              if (kDebugMode && dType.isNotEmpty) {
                debugPrint('Realtime IN: delta.type=$dType');
              }
              // Tipos: response.output_text.delta { text }
              if ((dType.contains('output_text') || dType.contains('text')) && delta['text'] is String) {
                onText?.call(delta['text']);
                handledText = true;
              }
              // Tipos de audio reales: response.audio.delta (no transcript)
              final isAudioEvent = type.startsWith('response.audio.');
              if ((isAudioEvent || dType.contains('output_audio')) && delta['audio'] is String) {
                try {
                  final bytes = base64Decode(delta['audio']);
                  onAudio?.call(bytes);
                  handledAudio = true;
                } catch (_) {}
              }
            } else if (delta is String) {
              // Algunos eventos envían delta como string directo
              if (type.contains('output_text') || type.contains('text')) {
                onText?.call(delta);
                handledText = true;
              }
              if (type.startsWith('response.audio.')) {
                try {
                  final bytes = base64Decode(delta);
                  onAudio?.call(bytes);
                  handledAudio = true;
                } catch (_) {}
              }
            }
            // Partes de salida en top-level (formatos anteriores)
            final output = evt['output'] ?? evt['content'];
            if (output is List) {
              for (final part in output) {
                if (part is Map) {
                  final pType = (part['type'] ?? '').toString();
                  if ((pType.contains('output_text') || pType.contains('text')) && part['text'] is String) {
                    if (!handledText) onText?.call(part['text']);
                    handledText = true;
                  }
                  if ((pType.contains('output_audio') || pType.contains('audio')) && part['audio'] is String) {
                    try {
                      if (!handledAudio) {
                        final bytes = base64Decode(part['audio']);
                        onAudio?.call(bytes);
                        handledAudio = true;
                      }
                    } catch (_) {}
                  }
                }
              }
            }

            // Salida anidada dentro de evt['response'] (formatos modernos en response.done/created)
            final resp = evt['response'];
            if (resp is Map) {
              // Extracción profunda (texto/audio)
              _extractAndEmitFromResponse(resp);
              // Buscar en response.output
              final rOutput = resp['output'];
              if (rOutput is List) {
                for (final part in rOutput) {
                  if (part is Map) {
                    final pType = (part['type'] ?? '').toString();
                    // Texto directo
                    if ((pType.contains('output_text') || pType.contains('text')) && part['text'] is String) {
                      if (!handledText) onText?.call(part['text']);
                      handledText = true;
                    }
                    // Texto en content array
                    if (part['content'] is List) {
                      for (final c in (part['content'] as List)) {
                        if (c is Map) {
                          final ct = (c['type'] ?? '').toString();
                          if ((ct.contains('output_text') || ct.contains('text')) && c['text'] is String) {
                            if (!handledText) onText?.call(c['text']);
                            handledText = true;
                          }
                          if ((ct.contains('output_audio') || ct.contains('audio')) && c['audio'] is String) {
                            try {
                              if (!handledAudio) {
                                final bytes = base64Decode(c['audio']);
                                onAudio?.call(bytes);
                                handledAudio = true;
                              }
                            } catch (_) {}
                          }
                        }
                      }
                    }
                    // Audio directo
                    if ((pType.contains('output_audio') || pType.contains('audio')) && part['audio'] is String) {
                      try {
                        if (!handledAudio) {
                          final bytes = base64Decode(part['audio']);
                          onAudio?.call(bytes);
                          handledAudio = true;
                        }
                      } catch (_) {}
                    }
                  }
                }
              }
              // Buscar en response.content
              final rContent = resp['content'];
              if (rContent is List) {
                for (final c in rContent) {
                  if (c is Map) {
                    final ct = (c['type'] ?? '').toString();
                    if ((ct.contains('output_text') || ct.contains('text')) && c['text'] is String) {
                      onText?.call(c['text']);
                    }
                    if ((ct.contains('output_audio') || ct.contains('audio')) && c['audio'] is String) {
                      try {
                        final bytes = base64Decode(c['audio']);
                        onAudio?.call(bytes);
                      } catch (_) {}
                    }
                  }
                }
              }
            }
            // Audio delta (variantes): evt['audio'] o evt['delta']
            if (type.startsWith('response.audio.') && !handledAudio) {
              String? b64;
              if (evt['audio'] is String) b64 = evt['audio'];
              if (b64 == null && evt['delta'] is Map && evt['delta']['audio'] is String) {
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
                } catch (_) {}
              }
            }
            // Compleción de respuesta SOLO cuando el servidor emite el final global
            if (type == 'response.done' || type == 'response.completed') {
              onCompleted?.call();
              // Detectar fallo compacto
              final resp = evt['response'];
              if (resp is Map) {
                final status = (resp['status'] ?? '').toString();
                if (status == 'failed') {
                  final err = (resp['status_details'] is Map) ? resp['status_details']['error'] : null;
                  final code = (err is Map) ? (err['code'] ?? '').toString() : '';
                  final msg = (err is Map) ? (err['message'] ?? '').toString() : '';
                  if (kDebugMode) {
                    debugPrint('Realtime response failed: $code $msg');
                  }
                  // Propagar como error para que capas superiores puedan colgar
                  onError?.call(Exception('response_failed:$code $msg'));
                }
              }
              _hasActiveResponse = false;
              // flags simplificados
            }
            // Fallback: si usamos VAD del servidor y tras committed aún no hay respuesta activa,
            // programamos una creación de respuesta que será cancelada si el servidor ya creó una.
            if (type == 'input_audio_buffer.committed' && _serverTurnDetection) {
              if (!_hasActiveResponse) {
                requestResponse(audio: true, text: true);
              }
            }
            // Señales del servidor VAD para input (marcan turnos)
            if (!_serverTurnDetection &&
                (type == 'input_audio_buffer.committed' || type == 'input_audio_buffer.speech_stopped')) {
              // Solo pedir respuesta automáticamente si NO usamos VAD del servidor
              requestResponse(audio: true, text: true);
            }
            // Capturar transcripciones del usuario
            if (type == 'conversation.item.input_audio_transcription.completed') {
              if (kDebugMode) {
                debugPrint('Realtime IN: transcripción evento completo: $evt');
              }
              final transcript = (evt['transcript'] ?? '').toString().trim();
              if (transcript.isNotEmpty) {
                if (kDebugMode) {
                  debugPrint('Realtime IN: transcripción usuario: "$transcript"');
                }
                onUserTranscription?.call(transcript);
              } else {
                // Intentar otros campos posibles
                final altTranscript = (evt['text'] ?? evt['content'] ?? '').toString().trim();
                if (altTranscript.isNotEmpty) {
                  if (kDebugMode) {
                    debugPrint('Realtime IN: transcripción usuario (alt): "$altTranscript"');
                  }
                  onUserTranscription?.call(altTranscript);
                }
              }
            }

            // Eliminado: envío de truncate para input_audio (causaba errores unsupported_content_type)
            if (type == 'error' && evt['error'] != null) {
              if (kDebugMode) {
                debugPrint('Realtime ERROR completo: ${evt['error']}');
              }
              onError?.call(Exception(evt['error'].toString()));
            }
          } else if (message is List<int>) {
            // Audio PCM16 recibido como frame binario
            try {
              final bytes = Uint8List.fromList(message);
              if (kDebugMode) {
                debugPrint('Realtime IN: binary audio chunk len=${bytes.length}');
              }
              onAudio?.call(bytes);
            } catch (e) {
              onError?.call(e);
            }
          }
        } catch (e) {
          onError?.call(e);
        }
      },
      onError: (e) {
        onError?.call(e);
        _connected = false;
      },
      onDone: () {
        _connected = false;
      },
    );

    // Esperar a que la sesión esté creada
    try {
      await sessionReady.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Realtime: timeout esperando session.created');
      }
    }
    // No esperar session.updated en versión simple
  }

  // Actualiza la voz de la sesión en caliente
  @override
  void updateVoice(String voice) {
    if (!_connected) return;
    _send({
      'type': 'session.update',
      'session': {'voice': voice},
    });
  }

  @override
  void sendText(String text) {
    if (!_connected) return;
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

  @override
  void appendAudio(List<int> bytes) {
    if (!_connected) return;
    _send({'type': 'input_audio_buffer.append', 'audio': base64Encode(bytes)});
    _bytesSinceCommit += bytes.length;
    _hasAppendedSinceConnect = true;
    _lastAppendAt = DateTime.now();
  }

  void commitInput() {
    if (!_connected) return;
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
    final sinceMs = _lastAppendAt == null ? 9999 : now.difference(_lastAppendAt!).inMilliseconds;
    if (sinceMs < 120) {
      if (_commitScheduled) return;
      final waitMs = 120 - sinceMs;
      _commitScheduled = true;
      Future.delayed(Duration(milliseconds: waitMs), () {
        if (!_connected) return;
        if (_bytesSinceCommit < 3200) {
          if (kDebugMode) {
            debugPrint('Realtime: commit diferido cancelado por bytes insuficientes ($_bytesSinceCommit)');
          }
          _commitScheduled = false;
          return;
        }
        if (kDebugMode) {
          debugPrint('Realtime OUT (deferred): input_audio_buffer.commit bytes=$_bytesSinceCommit');
        }
        _send({'type': 'input_audio_buffer.commit'});
        _bytesSinceCommit = 0;
        _commitScheduled = false;
      });
      return;
    }
    if (kDebugMode) {
      debugPrint('Realtime OUT: input_audio_buffer.commit bytes=$_bytesSinceCommit');
    }
    _send({'type': 'input_audio_buffer.commit'});
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
    if (!_connected) return;
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
      if (!_connected) return;
      if (_hasActiveResponse) {
        if (kDebugMode) {
          debugPrint('Realtime: cancelado response.create (respuesta activa detectada)');
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
        _send(incoming);
      }
      _send({
        'type': 'response.create',
        'response': {'modalities': modalities},
      });
      _responseCreateTimer = null;
    });
  }

  void cancelResponse() {
    if (!_connected) return;
    _send({'type': 'response.cancel'});
  }

  @override
  Future<void> close() async {
    if (_connected) {
      try {
        _responseCreateTimer?.cancel();
        _responseCreateTimer = null;
        await _channel?.sink.close();
      } catch (_) {}
      _connected = false;
    }
  }

  void _send(Map<String, dynamic> event) {
    if (!_connected) return;
    if (kDebugMode) {
      final t = event['type'];
      if (t != 'input_audio_buffer.append') {
        debugPrint('Realtime OUT: type=$t');
      }
    }
    _channel!.sink.add(jsonEncode(event));
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
      debugPrint('Realtime: resp extract -> texts=${texts.length}, audioChunks=${audioChunks.length}');
    }
    for (final s in texts) {
      onText?.call(s);
    }
    for (final ch in audioChunks) {
      onAudio?.call(ch);
    }
  }
}
