import 'package:ai_chan/call/domain/interfaces/i_call_message.dart';
import 'package:ai_chan/chat/domain/models/message.dart';
import 'package:ai_chan/shared/domain/enums/message_sender.dart';

/// Adapter que convierte un Message de chat a ICallMessage
/// Implementa el patrón Port-Adapter para aislar bounded contexts
class CallMessageAdapter implements ICallMessage {
  const CallMessageAdapter(this._message);
  final Message _message;

  @override
  String get id => _message.localId;

  @override
  String get content => _message.text;

  @override
  String get author =>
      _message.sender == MessageSender.user ? 'user' : 'assistant';

  @override
  DateTime get timestamp => _message.dateTime;

  @override
  bool get isUser => _message.sender == MessageSender.user;

  @override
  bool get isAssistant => _message.sender == MessageSender.assistant;
}
