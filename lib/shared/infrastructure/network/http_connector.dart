import 'package:http/http.dart' as http;

/// Central HTTP connector to allow tests to replace the global http client
/// with a fake implementation. Production code should use
/// `HttpConnector.client` or accept a `http.Client` parameter and default to
/// `HttpConnector.client` so tests can swap it.
class HttpConnector {
  static http.Client client = http.Client();

  /// Tests can replace the client with a fake implementation
  static void setClient(final http.Client c) {
    client = c;
  }

  /// Reset to default client
  static void reset() {
    client = http.Client();
  }
}
