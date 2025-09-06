import 'dart:convert';

import 'package:ai_chan/shared/utils/prefs_utils.dart';

import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/call/domain/models/call.dart';
import 'package:ai_chan/call/domain/models/call_message.dart';

/// Repositorio que persiste llamadas de voz usando SharedPreferences
class LocalCallRepository implements ICallRepository {
  static const String _callsKey = PrefsUtils.kVoiceCalls;

  @override
  Future<void> saveCall(final Call call) async {
    // Persist call data using SharedPreferences under dedicated keys.
    // Obtener llamadas existentes
    final callsMap = await _getAllCallsMap();

    // Guardar llamada (sin mensajes para evitar duplicación)
    final callToSave = call.copyWith(messages: []);
    callsMap[call.id] = callToSave.toMap();

    // Persistir llamadas
    try {
      await PrefsUtils.setRawString(_callsKey, jsonEncode(callsMap));
    } on Exception catch (_) {}

    // Guardar mensajes por separado
    if (call.messages.isNotEmpty) {
      final messagesMap = call.messages.asMap().map(
        (final index, final message) =>
            MapEntry(index.toString(), message.toMap()),
      );
      try {
        await PrefsUtils.setRawString(
          PrefsUtils.voiceMessagesKey(call.id),
          jsonEncode(messagesMap),
        );
      } on Exception catch (_) {}
    }
  }

  @override
  Future<Call?> getCall(final String id) async {
    final callsMap = await _getAllCallsMap();
    final callData = callsMap[id];

    if (callData == null) return null;

    // Crear llamada base
    final call = Call.fromMap(callData);

    // Cargar mensajes
    final messages = await getCallMessages(id);

    return call.copyWith(messages: messages);
  }

  @override
  Future<List<Call>> getAllCalls() async {
    final callsMap = await _getAllCallsMap();
    final calls = <Call>[];

    for (final callData in callsMap.values) {
      final call = Call.fromMap(callData);
      // Cargar mensajes para cada llamada
      final messages = await getCallMessages(call.id);
      calls.add(call.copyWith(messages: messages));
    }

    // Ordenar por fecha de inicio (más reciente primero)
    calls.sort((final a, final b) => b.startTime.compareTo(a.startTime));

    return calls;
  }

  @override
  Future<List<Call>> getCallsByDateRange(
    final DateTime from,
    final DateTime to,
  ) async {
    final allCalls = await getAllCalls();

    return allCalls.where((final call) {
      return call.startTime.isAfter(
            from.subtract(const Duration(seconds: 1)),
          ) &&
          call.startTime.isBefore(to.add(const Duration(seconds: 1)));
    }).toList();
  }

  @override
  Future<void> deleteCall(final String id) async {
    try {
      // Eliminar llamada
      final callsMap = await _getAllCallsMap();
      callsMap.remove(id);
      await PrefsUtils.setRawString(_callsKey, jsonEncode(callsMap));

      // Eliminar mensajes asociados
      await PrefsUtils.removeKey(PrefsUtils.voiceMessagesKey(id));
    } on Exception catch (_) {}
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
    } on Exception catch (_) {}
  }

  @override
  Future<void> updateCall(final Call call) async {
    // Mismo comportamiento que saveCall
    await saveCall(call);
  }

  @override
  Future<void> addMessageToCall(
    final String callId,
    final CallMessage message,
  ) async {
    final call = await getCall(callId);
    if (call == null) return;

    final updatedMessages = [...call.messages, message];
    final updatedCall = call.copyWith(messages: updatedMessages);

    await saveCall(updatedCall);
  }

  @override
  Future<List<CallMessage>> getCallMessages(final String callId) async {
    try {
      final messagesJson = await PrefsUtils.getRawString(
        PrefsUtils.voiceMessagesKey(callId),
      );
      if (messagesJson == null) return [];

      try {
        final messagesMap = jsonDecode(messagesJson) as Map<String, dynamic>;
        final messages = <CallMessage>[];

        // Ordenar por índice para mantener el orden
        final sortedEntries = messagesMap.entries.toList()
          ..sort(
            (final a, final b) => int.parse(a.key).compareTo(int.parse(b.key)),
          );

        for (final entry in sortedEntries) {
          final messageData = entry.value as Map<String, dynamic>;
          messages.add(CallMessage.fromMap(messageData));
        }

        return messages;
      } on Exception {
        // Si hay error parseando, retornar lista vacía
        return [];
      }
    } on Exception catch (_) {
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
      } on Exception {
        // Si hay error parseando, retornar mapa vacío
        return {};
      }
    } on Exception catch (_) {
      return {};
    }
  }
}
