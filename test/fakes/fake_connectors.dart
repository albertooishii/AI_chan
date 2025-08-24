import 'dart:async';

import 'package:ai_chan/core/network_connectors.dart';

/// Utilities for tests to register fake connector implementations.

class FakeSocket implements SocketLike {
  bool destroyed = false;
  @override
  void destroy() => destroyed = true;
}

class FakeChannel implements WsChannel {
  final _controller = StreamController<dynamic>();
  @override
  Stream<dynamic> get stream => _controller.stream;
  final _fakeSink = _FakeSink();
  @override
  WsSink get sink => _fakeSink;
  void addIncoming(dynamic m) => _controller.add(m);
  Future<void> close() async => await _controller.close();
}

class _FakeSink implements WsSink {
  final List<dynamic> sent = [];
  @override
  void add(dynamic m) => sent.add(m);
  @override
  Future<void> close() async {}
}

void registerFakeSocketConnector() {
  SocketConnector.setConnectImpl((host, port, {Duration? timeout}) async {
    return Future.value(FakeSocket());
  });
}

void registerFakeWebSocketConnector() {
  WebSocketConnector.setConnectImpl((uri, {headers}) {
    return FakeChannel();
  });
}
