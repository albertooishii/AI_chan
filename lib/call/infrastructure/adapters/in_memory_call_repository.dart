import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/call/domain/models/call.dart';
import 'package:ai_chan/call/domain/models/call_message.dart';
import 'package:flutter/foundation.dart';

/// Implementación en memoria del repositorio de llamadas
/// TODO: Migrar a implementación persistente (SQLite/Hive)
class InMemoryCallRepository implements ICallRepository {
  final Map<String, Call> _calls = {};
  final Map<String, List<CallMessage>> _callMessages = {};

  @override
  Future<void> saveCall(final Call call) async {
    _calls[call.id] = call;
    debugPrint('[InMemoryCallRepository] Call saved: ${call.id}');
  }

  @override
  Future<Call?> getCall(final String id) async {
    return _calls[id];
  }

  @override
  Future<List<Call>> getAllCalls() async {
    return _calls.values.toList()
      ..sort((final a, final b) => b.startTime.compareTo(a.startTime));
  }

  @override
  Future<List<Call>> getCallsByDateRange(
    final DateTime from,
    final DateTime to,
  ) async {
    return _calls.values
        .where(
          (final call) =>
              call.startTime.isAfter(from) && call.startTime.isBefore(to),
        )
        .toList()
      ..sort((final a, final b) => b.startTime.compareTo(a.startTime));
  }

  @override
  Future<void> deleteCall(final String id) async {
    _calls.remove(id);
    _callMessages.remove(id);
    debugPrint('[InMemoryCallRepository] Call deleted: $id');
  }

  @override
  Future<void> deleteAllCalls() async {
    _calls.clear();
    _callMessages.clear();
    debugPrint('[InMemoryCallRepository] All calls deleted');
  }

  @override
  Future<void> updateCall(final Call call) async {
    if (_calls.containsKey(call.id)) {
      _calls[call.id] = call;
      debugPrint('[InMemoryCallRepository] Call updated: ${call.id}');
    }
  }

  @override
  Future<void> addMessageToCall(
    final String callId,
    final CallMessage message,
  ) async {
    if (_calls.containsKey(callId)) {
      _callMessages.putIfAbsent(callId, () => []).add(message);
      debugPrint('[InMemoryCallRepository] Message added to call $callId');
    }
  }

  @override
  Future<List<CallMessage>> getCallMessages(final String callId) async {
    return _callMessages[callId] ?? [];
  }
}
