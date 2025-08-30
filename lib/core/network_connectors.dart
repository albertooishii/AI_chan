// allow-network
import 'dart:io';
import 'package:web_socket_channel/io.dart' as wsio;

/// Small injection points for network primitives so tests can override them
/// and prevent real network activity.

/// Minimal WebSocket-like interface used by transports/tests.
abstract class WsChannel {
  Stream<dynamic> get stream;
  WsSink get sink;
}

abstract class WsSink {
  void add(dynamic data);
  Future<void> close();
}

/// Minimal socket-like interface used by hasInternetConnection.
abstract class SocketLike {
  void destroy();
}

class _IoWsSinkAdapter implements WsSink {
  final dynamic _inner;
  _IoWsSinkAdapter(this._inner);
  @override
  void add(dynamic data) => _inner.add(data);
  @override
  Future<void> close() async {
    try {
      await _inner.close();
    } catch (_) {}
  }
}

class _IoWsChannelAdapter implements WsChannel {
  final wsio.IOWebSocketChannel _inner;
  _IoWsChannelAdapter(this._inner);
  @override
  Stream<dynamic> get stream => _inner.stream;
  @override
  WsSink get sink => _IoWsSinkAdapter(_inner.sink);
}

class _IoSocketAdapter implements SocketLike {
  final Socket _inner;
  _IoSocketAdapter(this._inner);
  @override
  void destroy() => _inner.destroy();
}

typedef WsConnectFn =
    WsChannel Function(Uri uri, {Map<String, String>? headers});
typedef SocketConnectFn =
    Future<SocketLike> Function(String host, int port, {Duration? timeout});

class WebSocketConnector {
  // default implementation uses IOWebSocketChannel wrapped in adapter
  static WsConnectFn connectImpl = (uri, {headers}) => _IoWsChannelAdapter(
    wsio.IOWebSocketChannel.connect(uri, headers: headers),
  );

  static WsChannel connect(Uri uri, {Map<String, String>? headers}) =>
      connectImpl(uri, headers: headers);

  /// Tests can replace the implementation to return a fake channel-like object
  static void setConnectImpl(WsConnectFn impl) {
    connectImpl = impl;
  }
}

class SocketConnector {
  static SocketConnectFn connectImpl =
      (host, port, {Duration? timeout}) async =>
          _IoSocketAdapter(await Socket.connect(host, port, timeout: timeout));

  static Future<SocketLike> connect(
    String host,
    int port, {
    Duration? timeout,
  }) => connectImpl(host, port, timeout: timeout);

  static void setConnectImpl(SocketConnectFn impl) {
    connectImpl = impl;
  }
}
