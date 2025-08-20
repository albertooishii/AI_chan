/// Fake Network Service for testing connectivity
class FakeNetworkService {
  bool _isConnected = true;
  final bool shouldFailOnCheck;
  final String errorMessage;
  final List<String> _requestLog = <String>[];

  FakeNetworkService({
    bool initiallyConnected = true,
    this.shouldFailOnCheck = false,
    this.errorMessage = 'Network check failed',
  }) : _isConnected = initiallyConnected;

  bool get isConnected => _isConnected;
  List<String> get requestLog => List.from(_requestLog);

  void setConnected(bool connected) {
    _isConnected = connected;
  }

  Future<bool> checkConnectivity() async {
    if (shouldFailOnCheck) {
      throw Exception(errorMessage);
    }
    return _isConnected;
  }

  Future<bool> pingServer(String url) async {
    _requestLog.add('PING: $url');

    if (shouldFailOnCheck) {
      throw Exception(errorMessage);
    }

    return _isConnected;
  }

  void clearRequestLog() {
    _requestLog.clear();
  }

  /// Factory for offline service
  factory FakeNetworkService.offline() {
    return FakeNetworkService(initiallyConnected: false);
  }

  /// Factory for failing service
  factory FakeNetworkService.failure([String? errorMsg]) {
    return FakeNetworkService(
      shouldFailOnCheck: true,
      errorMessage: errorMsg ?? 'Network service unavailable',
    );
  }
}

/// Fake HTTP Client for testing API calls
class FakeHttpClient {
  final Map<String, dynamic> _responses = <String, dynamic>{};
  final List<String> _requestLog = <String>[];
  final bool shouldFail;
  final int statusCode;
  final String errorMessage;
  int requestDelay = 0;

  FakeHttpClient({
    this.shouldFail = false,
    this.statusCode = 200,
    this.errorMessage = 'HTTP request failed',
    this.requestDelay = 0,
  });

  List<String> get requestLog => List.from(_requestLog);

  void setResponse(String endpoint, dynamic response) {
    _responses[endpoint] = response;
  }

  void clearResponses() {
    _responses.clear();
  }

  void clearRequestLog() {
    _requestLog.clear();
  }

  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? headers,
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
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
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
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
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
    String url, {
    Map<String, String>? headers,
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

  /// Factory for slow responses
  factory FakeHttpClient.slow(int delayMs) {
    return FakeHttpClient(requestDelay: delayMs);
  }

  /// Factory for failed requests
  factory FakeHttpClient.failure({int statusCode = 500, String? errorMsg}) {
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
}

/// Fake WebSocket Client for testing real-time communication
class FakeWebSocketClient {
  bool _isConnected = false;
  final List<String> _messageLog = <String>[];
  final List<String> _sentMessages = <String>[];
  final bool shouldFailConnection;
  final String errorMessage;

  FakeWebSocketClient({
    this.shouldFailConnection = false,
    this.errorMessage = 'WebSocket connection failed',
  });

  bool get isConnected => _isConnected;
  List<String> get messageLog => List.from(_messageLog);
  List<String> get sentMessages => List.from(_sentMessages);

  Future<void> connect(String url) async {
    if (shouldFailConnection) {
      throw Exception(errorMessage);
    }
    _isConnected = true;
  }

  Future<void> disconnect() async {
    _isConnected = false;
  }

  void sendMessage(String message) {
    if (!_isConnected) {
      throw StateError('WebSocket not connected');
    }
    _sentMessages.add(message);
  }

  void simulateIncomingMessage(String message) {
    if (_isConnected) {
      _messageLog.add(message);
    }
  }

  void clearLogs() {
    _messageLog.clear();
    _sentMessages.clear();
  }

  factory FakeWebSocketClient.failure([String? errorMsg]) {
    return FakeWebSocketClient(
      shouldFailConnection: true,
      errorMessage: errorMsg ?? 'WebSocket connection unavailable',
    );
  }
}
