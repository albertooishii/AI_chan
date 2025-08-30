import 'dart:convert';

import 'package:ai_chan/shared/utils/prefs_utils.dart';

import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';
import 'package:ai_chan/voice/domain/models/voice_call.dart';
import 'package:ai_chan/voice/domain/models/voice_message.dart';

/// Repositorio que persiste llamadas de voz usando SharedPreferences
class LocalVoiceCallRepository implements IVoiceCallRepository {
  static const String _callsKey = PrefsUtils.kVoiceCalls;

  @override
  Future<void> saveCall(VoiceCall call) async {
    // Persist call data using SharedPreferences under dedicated keys.
    // Obtener llamadas existentes
    final callsMap = await _getAllCallsMap();

    // Guardar llamada (sin mensajes para evitar duplicación)
    final callToSave = call.copyWith(messages: []);
    callsMap[call.id] = callToSave.toMap();

    // Persistir llamadas
    try {
      await PrefsUtils.setRawString(_callsKey, jsonEncode(callsMap));
    } catch (_) {}

    // Guardar mensajes por separado
    if (call.messages.isNotEmpty) {
      final messagesMap = call.messages.asMap().map(
        (index, message) => MapEntry(index.toString(), message.toMap()),
      );
      try {
        await PrefsUtils.setRawString(
          PrefsUtils.voiceMessagesKey(call.id),
          jsonEncode(messagesMap),
        );
      } catch (_) {}
    }
  }

  @override
  Future<VoiceCall?> getCall(String id) async {
    final callsMap = await _getAllCallsMap();
    final callData = callsMap[id];

    if (callData == null) return null;

    // Crear llamada base
    final call = VoiceCall.fromMap(callData);

    // Cargar mensajes
    final messages = await getCallMessages(id);

    return call.copyWith(messages: messages);
  }

  @override
  Future<List<VoiceCall>> getAllCalls() async {
    final callsMap = await _getAllCallsMap();
    final calls = <VoiceCall>[];

    for (final callData in callsMap.values) {
      final call = VoiceCall.fromMap(callData);
      // Cargar mensajes para cada llamada
      final messages = await getCallMessages(call.id);
      calls.add(call.copyWith(messages: messages));
    }

    // Ordenar por fecha de inicio (más reciente primero)
    calls.sort((a, b) => b.startTime.compareTo(a.startTime));

    return calls;
  }

  @override
  Future<List<VoiceCall>> getCallsByDateRange(
    DateTime from,
    DateTime to,
  ) async {
    final allCalls = await getAllCalls();

    return allCalls.where((call) {
      return call.startTime.isAfter(
            from.subtract(const Duration(seconds: 1)),
          ) &&
          call.startTime.isBefore(to.add(const Duration(seconds: 1)));
    }).toList();
  }

  @override
  Future<void> deleteCall(String id) async {
    try {
      // Eliminar llamada
      final callsMap = await _getAllCallsMap();
      callsMap.remove(id);
      await PrefsUtils.setRawString(_callsKey, jsonEncode(callsMap));

      // Eliminar mensajes asociados
      await PrefsUtils.removeKey(PrefsUtils.voiceMessagesKey(id));
    } catch (_) {}
  }

  @override
  Future<void> deleteAllCalls() async {
    try {
      // Obtener todas las llamadas para limpiar sus mensajes
      final callsMap = await _getAllCallsMap();
      for (final callId in callsMap.keys) {
        await PrefsUtils.removeKey(PrefsUtils.voiceMessagesKey(callId));
      }

      // Limpiar llamadas
      await PrefsUtils.removeKey(_callsKey);
    } catch (_) {}
  }

  @override
  Future<void> updateCall(VoiceCall call) async {
    // Mismo comportamiento que saveCall
    await saveCall(call);
  }

  @override
  Future<void> addMessageToCall(String callId, VoiceMessage message) async {
    final call = await getCall(callId);
    if (call == null) return;

    final updatedMessages = [...call.messages, message];
    final updatedCall = call.copyWith(messages: updatedMessages);

    await saveCall(updatedCall);
  }

  @override
  Future<List<VoiceMessage>> getCallMessages(String callId) async {
    try {
      final messagesJson = await PrefsUtils.getRawString(
        PrefsUtils.voiceMessagesKey(callId),
      );
      if (messagesJson == null) return [];

      try {
        final messagesMap = jsonDecode(messagesJson) as Map<String, dynamic>;
        final messages = <VoiceMessage>[];

        // Ordenar por índice para mantener el orden
        final sortedEntries = messagesMap.entries.toList()
          ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

        for (final entry in sortedEntries) {
          final messageData = entry.value as Map<String, dynamic>;
          messages.add(VoiceMessage.fromMap(messageData));
        }

        return messages;
      } catch (e) {
        // Si hay error parseando, retornar lista vacía
        return [];
      }
    } catch (_) {
      return [];
    }
  }

  /// Obtiene el mapa de todas las llamadas desde SharedPreferences
  Future<Map<String, dynamic>> _getAllCallsMap() async {
    try {
      final callsJson = await PrefsUtils.getRawString(_callsKey);
      if (callsJson == null) return {};
      try {
        return jsonDecode(callsJson) as Map<String, dynamic>;
      } catch (e) {
        // Si hay error parseando, retornar mapa vacío
        return {};
      }
    } catch (_) {
      return {};
    }
  }
}
