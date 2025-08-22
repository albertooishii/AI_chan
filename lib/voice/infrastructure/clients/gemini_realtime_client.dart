import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/utils/debug_call_logger/debug_call_logger.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';

/// Orquestador que emula comportamiento realtime para Gemini usando Google STT/TTS.
import '../../../core/interfaces/i_realtime_client.dart';

class GeminiCallOrchestrator implements IRealtimeClient {
  final String model;
  final void Function(String textDelta)? onText;
  final void Function(Uint8List audioChunk)? onAudio;
  final void Function()? onCompleted;
  final void Function(Object err)? onError;
  final void Function(String userTranscription)? onUserTranscription;

  bool _connected = false;
  @override
  bool get isConnected => _connected;

  final List<int> _pendingAudio = [];
  Timer? _deferredTranscribeTimer;
  // Commit-on-silence fields (mimic OpenAI realtime client behavior)
  int _bytesSinceCommit = 0;
  DateTime? _lastAppendAt;
  bool _commitScheduled = false;
  String? _systemPrompt;
  String _voice = 'default';

  GeminiCallOrchestrator({
    String? model,
    this.onText,
    this.onAudio,
    this.onCompleted,
    this.onError,
    this.onUserTranscription,
  }) : model = model ?? Config.requireGoogleRealtimeModel();
  // Para el flujo realtime 'google' usamos un modelo específico configurable
  // (GOOGLE_REALTIME_MODEL) y fallamos si no está presente.

  @override
  Future<void> connect({
    required String systemPrompt,
    String voice = 'default',
    // Compatibilidad con llamadas que pasan parámetros detallados
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    // Actualmente Gemini emula la conexión; aceptamos y guardamos/ignorar opciones
    _connected = true;
    _systemPrompt = systemPrompt;
    _voice = voice;
    if (kDebugMode) {
      debugPrint('GeminiRealtime: connect emulated (model=$model) voice=$_voice');
    }
    // Nota: podríamos usar los valores de options si en el futuro se requiere
    return;
  }

  @override
  void updateVoice(String voice) {}

  @override
  void sendText(String text) {
    if (!_connected) return;
    // Directly process provided text as if it were a user transcription
    _sendTranscriptToGemini(text);
  }

  @override
  void appendAudio(List<int> bytes) {
    if (!_connected) return;
    if (bytes.isEmpty) return;
    _pendingAudio.addAll(bytes);
    _bytesSinceCommit += bytes.length;
    _lastAppendAt = DateTime.now();

    // Cancel any previous deferred transcribe (legacy) and schedule a commit-on-silence.
    _deferredTranscribeTimer?.cancel();

    // Commit debounce: wait 120ms since last append before committing (like OpenAI)
    const commitDebounceMs = 120;
    if (_commitScheduled) {
      // A commit is already scheduled; reschedule by cancelling and scheduling below
      _commitScheduled = false;
    }
    _commitScheduled = true;
    _deferredTranscribeTimer = Timer(const Duration(milliseconds: commitDebounceMs), () async {
      _commitScheduled = false;
      try {
        // Minimum bytes guard to avoid empty commits (~100ms of audio at 16k mono ~= 3200 bytes)
        const minBytes = 3200;
        final now = DateTime.now();
        final sinceMs = _lastAppendAt == null ? 9999 : now.difference(_lastAppendAt!).inMilliseconds;
        if (sinceMs < commitDebounceMs) {
          // Too recent: reschedule to honor debounce
          if (kDebugMode) debugPrint('GeminiOrch: commit deferred, sinceMs=$sinceMs');
          _commitScheduled = true;
          _deferredTranscribeTimer = Timer(Duration(milliseconds: commitDebounceMs - sinceMs), () async {
            _commitScheduled = false;
            try {
              if (_bytesSinceCommit >= minBytes && _pendingAudio.isNotEmpty) {
                await _processPendingAudioChunk();
              } else {
                _bytesSinceCommit = 0;
              }
            } catch (e) {
              if (onError != null) onError!(e);
              if (kDebugMode) debugPrint('GeminiOrch: STT/commit error $e');
            }
          });
          return;
        }
        if (_bytesSinceCommit >= minBytes && _pendingAudio.isNotEmpty) {
          await _processPendingAudioChunk();
        } else {
          // Not enough audio accumulated; just clear counters conservatively
          _bytesSinceCommit = 0;
        }
      } catch (e) {
        if (onError != null) onError!(e);
        if (kDebugMode) debugPrint('GeminiOrch: STT/commit error $e');
      }
    });
  }

  Future<void> _processPendingAudioChunk() async {
    if (_pendingAudio.isEmpty) return;
    final data = List<int>.from(_pendingAudio);
    _pendingAudio.clear();
    // Write bytes to a temporary file and call the STT adapter which expects a path.
    try {
      final tmpDir = await Directory.systemTemp.createTemp('gemini_stt');
      final tmpFile = File('${tmpDir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav');

      // Build a valid WAV file from raw PCM16 bytes (mono). This decouples the
      // recorder format from the STT adapter which expects a file container.
      try {
        final wavBytes = _buildWavFromPcm(data, sampleRate: 16000);
        await tmpFile.writeAsBytes(wavBytes);
      } catch (e) {
        // Fallback: write raw bytes if WAV building fails
        await tmpFile.writeAsBytes(data);
      }

      final ISttService stt = di.getSttServiceForProvider('google');
      final text = await stt.transcribeAudio(tmpFile.path);
      try {
        await tmpFile.delete();
      } catch (_) {}
      if (text != null && text.trim().isNotEmpty) {
        onUserTranscription?.call(text.trim());
        await _sendTranscriptToGemini(text.trim());
      }
    } catch (e) {
      if (onError != null) onError!(e);
    }
  }

  /// Procesa inmediatamente cualquier audio pendiente (forzar commit desde el controlador).
  @override
  Future<void> commitPendingAudio() async {
    // Cancel any scheduled deferred commit and process now
    _deferredTranscribeTimer?.cancel();
    _commitScheduled = false;
    try {
      if (_pendingAudio.isNotEmpty) {
        await _processPendingAudioChunk();
        _bytesSinceCommit = 0;
      }
    } catch (e) {
      if (onError != null) onError!(e);
    }
  }

  // Construye un WAV (RIFF) simple con PCM16 mono a partir de bytes PCM crudos.
  Uint8List _buildWavFromPcm(List<int> pcmData, {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;

    final wav = BytesBuilder();
    wav.add('RIFF'.codeUnits);
    wav.add(_intToBytes(fileSize, 4));
    wav.add('WAVE'.codeUnits);
    wav.add('fmt '.codeUnits);
    wav.add(_intToBytes(16, 4)); // chunk size
    wav.add(_intToBytes(1, 2)); // audio format (PCM)
    wav.add(_intToBytes(channels, 2));
    wav.add(_intToBytes(sampleRate, 4));
    wav.add(_intToBytes(byteRate, 4));
    wav.add(_intToBytes(blockAlign, 2));
    wav.add(_intToBytes(bitsPerSample, 2));
    wav.add('data'.codeUnits);
    wav.add(_intToBytes(dataSize, 4));
    wav.add(pcmData);
    return Uint8List.fromList(wav.toBytes());
  }

  List<int> _intToBytes(int value, int bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes; i++) {
      result.add((value >> (8 * i)) & 0xFF);
    }
    return result;
  }

  Future<void> _sendTranscriptToGemini(String transcript) async {
    try {
      final IAIService ai = di.getAIServiceForModel(model);
      // Use the adapter's sendMessage with a minimal history to get a response map
      // Prepare options: include model and, if available, the parsed SystemPrompt
      final opts = <String, dynamic>{'model': model};
      if (_systemPrompt != null && _systemPrompt!.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(_systemPrompt!);
          // Convert to SystemPrompt object so adapters/runtimes get the structured prompt
          try {
            opts['systemPromptObj'] = SystemPrompt.fromJson(decoded as Map<String, dynamic>);
          } catch (_) {
            // If conversion fails, fallback to raw decoded map
            opts['systemPromptObj'] = decoded;
          }
          // Also include raw system prompt string for runtimes that prefer the original text
          opts['systemPromptRaw'] = _systemPrompt;
        } catch (_) {}
      }

      // Construir payload de mensajes; incluir system como mensaje si disponemos del raw
      final messagesPayload = <Map<String, String>>[];
      try {
        final sysRaw = opts['systemPromptRaw'] as String?;
        if (sysRaw != null && sysRaw.trim().isNotEmpty) {
          // Gemini expects 'model' for system-level role
          messagesPayload.add({'role': 'model', 'content': sysRaw});
        }
      } catch (_) {}
      messagesPayload.add({'role': 'user', 'content': transcript});

      // Loggear payload enviado para debug
      try {
        Log.d('GeminiOrch OUT messagesPayload=${messagesPayload.map((m) => m['role']).toList()}');
      } catch (_) {}

      final respMap = await ai.sendMessage(messages: messagesPayload, options: opts);
      // Guardar respMap para debug si es necesario
      try {
        await debugLogCallPrompt('gemini_orch_respmap', {
          'transcript_preview': transcript.length > 400 ? transcript.substring(0, 400) : transcript,
          'opts_keys': opts.keys.toList(),
          'resp_preview': respMap.toString().length > 2000 ? respMap.toString().substring(0, 2000) : respMap.toString(),
        });
      } catch (_) {}

      final text = (respMap['text'] ?? respMap['response'] ?? '')?.toString() ?? '';
      if (text.isNotEmpty) {
        onText?.call(text);
        try {
          // Detect control tags and remove them from the text to synthesize.
          final hasEnd = RegExp(r'\[\/?end_call\]').hasMatch(text);
          final clean = text
              .replaceAll(RegExp(r'\[\/?start_call\]'), '')
              .replaceAll(RegExp(r'\[\/?end_call\]'), '')
              .trim();

          // If the message contained only an end_call tag, trigger hangup and skip TTS.
          if (hasEnd && clean.isEmpty) {
            try {
              await debugLogCallPrompt('gemini_orch_control_tag', {'tag': '[end_call][/end_call]', 'opts': opts});
            } catch (_) {}
            // Notify UI/consumer that call ended
            onText?.call('[end_call][/end_call]');
            return;
          }

          if (clean.isEmpty) {
            // Nothing left to synthesize (could be only start_call tag), skip TTS
            return;
          }

          final ITtsService tts = di.getTtsServiceForProvider('google');
          try {
            // Request LINEAR16/WAV output so we receive PCM-friendly data.
            final filePath = await tts.synthesizeToFile(
              text: clean,
              options: {'audioEncoding': 'LINEAR16', 'sampleRateHertz': 24000, 'format': 'wav', 'noCache': true},
            );
            if (filePath != null && filePath.isNotEmpty) {
              try {
                final bytes = await File(filePath).readAsBytes();
                final wav = Uint8List.fromList(bytes);
                final pcm = _extractPcmFromWav(wav);
                onAudio?.call(pcm);
              } catch (e) {
                if (kDebugMode) debugPrint('GeminiOrch: failed reading TTS file $e');
              } finally {
                // Attempt to remove any temp file produced by TTS to avoid persistent cache
                try {
                  final f = File(filePath);
                  if (await f.exists()) await f.delete();
                } catch (_) {}
              }
            }
          } catch (e) {
            if (kDebugMode) debugPrint('GeminiOrch: TTS error $e');
          }
        } catch (_) {}

        // Si no hubo texto ni audio, loguear para diagnóstico
        if ((text.isEmpty) && _pendingAudio.isEmpty) {
          try {
            await debugLogCallPrompt('gemini_orch_no_text_no_audio', {
              'transcript': transcript,
              'opts': opts,
              'respMap': respMap,
            });
          } catch (_) {}
        }
      }
      onCompleted?.call();
    } catch (e) {
      if (onError != null) onError!(e);
    }
  }

  // Busca el chunk 'data' en un WAV (bytes) y devuelve solo los bytes de audio PCM.
  // Si no parece ser WAV o no se encuentra el chunk, devuelve los bytes originales.
  Uint8List _extractPcmFromWav(Uint8List bytes) {
    try {
      // Buscar la ocurrencia ASCII de 'data'
      for (int i = 0; i < bytes.length - 4; i++) {
        if (bytes[i] == 0x64 && bytes[i + 1] == 0x61 && bytes[i + 2] == 0x74 && bytes[i + 3] == 0x61) {
          final size =
              (bytes[i + 4] & 0xFF) |
              ((bytes[i + 5] & 0xFF) << 8) |
              ((bytes[i + 6] & 0xFF) << 16) |
              ((bytes[i + 7] & 0xFF) << 24);
          final dataStart = i + 8;
          final dataEnd = (dataStart + size) <= bytes.length ? dataStart + size : bytes.length;
          return bytes.sublist(dataStart, dataEnd);
        }
      }
    } catch (_) {}
    return bytes; // fallback: no modificación
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    _deferredTranscribeTimer?.cancel();
    // If we have pending audio, process it (STT path)
    if (_pendingAudio.isNotEmpty) {
      _processPendingAudioChunk();
      return;
    }

    // If caller explicitly requested audio, ask the model to respond now in
    // natural speech (no control tags). This avoids the common fallback where
    // sending the generic incoming-call notice makes the model reply again
    // with only the control tag ("[start_call][/start_call]").
    if (audio) {
      final acceptPrompt =
          'El usuario ha aceptado la llamada. NO respondas con etiquetas de control. RESPONDE AHORA en voz natural y proporciona un saludo breve (una o dos frases).';
      _sendTranscriptToGemini(acceptPrompt).catchError((e) {
        if (onError != null) onError!(e);
      });
      return;
    }

    // If caller requested text-only and we have a system prompt, send a short
    // incoming-call notice so the model can emit control tags (phase 1).
    if (text && _systemPrompt != null && _systemPrompt!.trim().isNotEmpty) {
      final incomingCallNotice =
          'El usuario ha iniciado una llamada. Responde SOLO con "[start_call][/start_call]" para aceptar o "[end_call][/end_call]" para rechazar.';
      _sendTranscriptToGemini(incomingCallNotice).catchError((e) {
        if (onError != null) onError!(e);
      });
      return;
    }

    // Nothing to do: no pending audio and no system prompt to request
    return;
  }

  @override
  Future<void> close() async {
    _deferredTranscribeTimer?.cancel();
    _pendingAudio.clear();
    _connected = false;
  }
}
