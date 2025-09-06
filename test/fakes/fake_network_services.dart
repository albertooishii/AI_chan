/// Fake Network Service for testing connectivity
class FakeNetworkService {
  FakeNetworkService({
    final bool initiallyConnected = true,
    this.shouldFailOnCheck = false,
    this.errorMessage = 'Network check failed',
  }) : _isConnected = initiallyConnected;

  /// Factory for offline service
  factory FakeNetworkService.offline() {
    return FakeNetworkService(initiallyConnected: false);
  }

  /// Factory for failing service
  factory FakeNetworkService.failure([final String? errorMsg]) {
    return FakeNetworkService(
      shouldFailOnCheck: true,
      errorMessage: errorMsg ?? 'Network service unavailable',
    );
  }
  bool _isConnected = true;
  final bool shouldFailOnCheck;
  final String errorMessage;
  final List<String> _requestLog = <String>[];

  bool get isConnected => _isConnected;
  List<String> get requestLog => List.from(_requestLog);

  void setConnected(final bool connected) {
    _isConnected = connected;
  }

  Future<bool> checkConnectivity() async {
    if (shouldFailOnCheck) {
      throw Exception(errorMessage);
    }
    return _isConnected;
  }

  Future<bool> pingServer(final String url) async {
    _requestLog.add('PING: $url');

    if (shouldFailOnCheck) {
      throw Exception(errorMessage);
    }

    return _isConnected;
  }

  void clearRequestLog() {
    _requestLog.clear();
  }
}

/// Fake HTTP Client for testing API calls
class FakeHttpClient {
  FakeHttpClient({
    this.shouldFail = false,
    this.statusCode = 200,
    this.errorMessage = 'HTTP request failed',
    this.requestDelay = 0,
  });

  /// Factory for slow responses
  factory FakeHttpClient.slow(final int delayMs) {
    return FakeHttpClient(requestDelay: delayMs);
  }

  /// Factory for failed requests
  factory FakeHttpClient.failure({
    final int statusCode = 500,
    final String? errorMsg,
  }) {
    return FakeHttpClient(
      shouldFail: true,
      statusCode: statusCode,
      errorMessage: errorMsg ?? 'HTTP request failed',
    );
  }

  /// Factory for not found responses
  factory FakeHttpClient.notFound() {
    return FakeHttpClient(statusCode: 404);
  }

  /// Factory for unauthorized responses
  factory FakeHttpClient.unauthorized() {
    return FakeHttpClient(statusCode: 401);
  }
  final Map<String, dynamic> _responses = <String, dynamic>{};
  final List<String> _requestLog = <String>[];
  final bool shouldFail;
  final int statusCode;
  final String errorMessage;
  int requestDelay = 0;

  List<String> get requestLog => List.from(_requestLog);

  void setResponse(final String endpoint, final dynamic response) {
    _responses[endpoint] = response;
  }

  void clearResponses() {
    _responses.clear();
  }

  void clearRequestLog() {
    _requestLog.clear();
  }

  Future<Map<String, dynamic>> get(
    final String url, {
    final Map<String, String>? headers,
  }) async {
    _requestLog.add('GET: $url');

    if (requestDelay > 0) {
      await Future.delayed(Duration(milliseconds: requestDelay));
    }

    if (shouldFail) {
      throw Exception(errorMessage);
    }

    final response = _responses[url] ?? {'message': 'Mock response for $url'};

    return {
      'statusCode': statusCode,
      'data': response,
      'headers': headers ?? <String, String>{},
    };
  }

  Future<Map<String, dynamic>> post(
    final String url, {
    final Map<String, dynamic>? body,
    final Map<String, String>? headers,
  }) async {
    _requestLog.add('POST: $url');

    if (requestDelay > 0) {
      await Future.delayed(Duration(milliseconds: requestDelay));
    }

    if (shouldFail) {
      throw Exception(errorMessage);
    }

    final response =
        _responses[url] ?? {'message': 'Mock POST response for $url'};

    return {
      'statusCode': statusCode,
      'data': response,
      'headers': headers ?? <String, String>{},
      'requestBody': body,
    };
  }

  Future<Map<String, dynamic>> put(
    final String url, {
    final Map<String, dynamic>? body,
    final Map<String, String>? headers,
  }) async {
    _requestLog.add('PUT: $url');

    if (requestDelay > 0) {
      await Future.delayed(Duration(milliseconds: requestDelay));
    }

    if (shouldFail) {
      throw Exception(errorMessage);
    }

    final response =
        _responses[url] ?? {'message': 'Mock PUT response for $url'};

    return {
      'statusCode': statusCode,
      'data': response,
      'headers': headers ?? <String, String>{},
      'requestBody': body,
    };
  }

  Future<Map<String, dynamic>> delete(
    final String url, {
    final Map<String, String>? headers,
  }) async {
    _requestLog.add('DELETE: $url');

    if (requestDelay > 0) {
      await Future.delayed(Duration(milliseconds: requestDelay));
    }

    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return {
      'statusCode': statusCode,
      'data': {'message': 'Resource deleted'},
      'headers': headers ?? <String, String>{},
    };
  }
}

/// Fake WebSocket Client for testing real-time communication
class FakeWebSocketClient {
  FakeWebSocketClient({
    this.shouldFailConnection = false,
    this.errorMessage = 'WebSocket connection failed',
  });

  factory FakeWebSocketClient.failure([final String? errorMsg]) {
    return FakeWebSocketClient(
      shouldFailConnection: true,
      errorMessage: errorMsg ?? 'WebSocket connection unavailable',
    );
  }
  bool _isConnected = false;
  final List<String> _messageLog = <String>[];
  final List<String> _sentMessages = <String>[];
  final bool shouldFailConnection;
  final String errorMessage;

  bool get isConnected => _isConnected;
  List<String> get messageLog => List.from(_messageLog);
  List<String> get sentMessages => List.from(_sentMessages);

  Future<void> connect(final String url) async {
    if (shouldFailConnection) {
      throw Exception(errorMessage);
    }
    _isConnected = true;
  }

  Future<void> disconnect() async {
    _isConnected = false;
  }

  void sendMessage(final String message) {
    if (!_isConnected) {
      throw StateError('WebSocket not connected');
    }
    _sentMessages.add(message);
  }

  void simulateIncomingMessage(final String message) {
    if (_isConnected) {
      _messageLog.add(message);
    }
  }

  void clearLogs() {
    _messageLog.clear();
    _sentMessages.clear();
  }
}
