import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/core/config.dart';

/// Orquestador que emula comportamiento realtime para Gemini usando Google STT/TTS.
class GeminiCallOrchestrator {
  final String model;
  final void Function(String textDelta)? onText;
  final void Function(Uint8List audioChunk)? onAudio;
  final void Function()? onCompleted;
  final void Function(Object err)? onError;
  final void Function(String userTranscription)? onUserTranscription;

  bool _connected = false;
  bool get isConnected => _connected;

  final List<int> _pendingAudio = [];
  Timer? _deferredTranscribeTimer;

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

  Future<void> connect({
    required String systemPrompt,
    String voice = 'default',
  }) async {
    _connected = true;
    return;
  }

  void updateVoice(String voice) {}

  void appendAudio(List<int> bytes) {
    if (!_connected) return;
    _pendingAudio.addAll(bytes);
    _deferredTranscribeTimer?.cancel();
    _deferredTranscribeTimer = Timer(
      const Duration(milliseconds: 300),
      () async {
        try {
          await _processPendingAudioChunk();
        } catch (e) {
          if (onError != null) onError!(e);
          if (kDebugMode) debugPrint('GeminiOrch: STT error $e');
        }
      },
    );
  }

  Future<void> _processPendingAudioChunk() async {
    if (_pendingAudio.isEmpty) return;
    final data = List<int>.from(_pendingAudio);
    _pendingAudio.clear();
    // Write bytes to a temporary file and call the STT adapter which expects a path.
    try {
      final tmpDir = await Directory.systemTemp.createTemp('gemini_stt');
      final tmpFile = File(
        '${tmpDir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await tmpFile.writeAsBytes(data);
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

  Future<void> _sendTranscriptToGemini(String transcript) async {
    try {
      final IAIService ai = di.getAIServiceForModel(model);
      // Use the adapter's sendMessage with a minimal history to get a response map
      final respMap = await ai.sendMessage(
        messages: [
          {'role': 'user', 'content': transcript},
        ],
        options: {'model': model},
      );
      final text =
          (respMap['text'] ?? respMap['response'] ?? '')?.toString() ?? '';
      if (text.isNotEmpty) {
        onText?.call(text);
        final ITtsService tts = di.getTtsServiceForProvider('google');
        try {
          final filePath = await tts.synthesizeToFile(text: text);
          if (filePath != null && filePath.isNotEmpty) {
            try {
              final bytes = await File(filePath).readAsBytes();
              onAudio?.call(Uint8List.fromList(bytes));
            } catch (e) {
              if (kDebugMode) {
                debugPrint('GeminiOrch: failed reading TTS file $e');
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('GeminiOrch: TTS error $e');
        }
      }
      onCompleted?.call();
    } catch (e) {
      if (onError != null) onError!(e);
    }
  }

  void requestResponse({bool audio = true, bool text = true}) {
    _deferredTranscribeTimer?.cancel();
    _processPendingAudioChunk();
  }

  Future<void> close() async {
    _deferredTranscribeTimer?.cancel();
    _pendingAudio.clear();
    _connected = false;
  }
}
