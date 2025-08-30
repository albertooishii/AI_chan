import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// A minimal fake http.Client for tests. It matches on URL paths and returns
/// canned responses. Extend as needed for specific test cases.
class FakeHttpClient implements http.Client {
  final Map<Pattern, http.Response> _routes = {};

  /// Register a canned response for a URL pattern.
  void when(Pattern urlPattern, http.Response response) {
    _routes[urlPattern] = response;
  }

  http.Response _findResponse(Uri url) {
    for (final entry in _routes.entries) {
      if (RegExp(entry.key.toString()).hasMatch(url.toString())) {
        return entry.value;
      }
    }
    // Default: return 404 with empty body to avoid real network.
    return http.Response('', 404);
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> put(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> patch(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> delete(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) async {
    return _findResponse(url);
  }

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final r = _findResponse(url);
    return r.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final r = _findResponse(url);
    return Uint8List.fromList(r.bodyBytes);
  }

  @override
  void close() {}

  // The send method returns a StreamedResponse; for simplicity we provide a basic
  // conversion: use the request url to find a canned Response and convert it.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = _findResponse(request.url);
    final stream = Stream.fromIterable([r.bodyBytes]);
    return http.StreamedResponse(
      stream,
      r.statusCode,
      headers: r.headers,
      reasonPhrase: r.reasonPhrase,
    );
  }
}
