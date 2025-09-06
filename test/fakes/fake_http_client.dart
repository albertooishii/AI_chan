import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// A minimal fake http.Client for tests. It matches on URL paths and returns
/// canned responses. Extend as needed for specific test cases.
class FakeHttpClient implements http.Client {
  final Map<Pattern, http.Response> _routes = {};

  /// Register a canned response for a URL pattern.
  void when(final Pattern urlPattern, final http.Response response) {
    _routes[urlPattern] = response;
  }

  http.Response _findResponse(final Uri url) {
    for (final entry in _routes.entries) {
      if (RegExp(entry.key.toString()).hasMatch(url.toString())) {
        return entry.value;
      }
    }
    // Default: return 404 with empty body to avoid real network.
    return http.Response('', 404);
  }

  @override
  Future<http.Response> get(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> post(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
    final Encoding? encoding,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> put(
    final Uri url, {
    final Object? body,
    final Encoding? encoding,
    final Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> patch(
    final Uri url, {
    final Object? body,
    final Encoding? encoding,
    final Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> delete(
    final Uri url, {
    final Object? body,
    final Encoding? encoding,
    final Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<http.Response> head(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    return _findResponse(url);
  }

  @override
  Future<String> read(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final r = _findResponse(url);
    return r.body;
  }

  @override
  Future<Uint8List> readBytes(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final r = _findResponse(url);
    return Uint8List.fromList(r.bodyBytes);
  }

  @override
  void close() {}

  // The send method returns a StreamedResponse; for simplicity we provide a basic
  // conversion: use the request url to find a canned Response and convert it.
  @override
  Future<http.StreamedResponse> send(final http.BaseRequest request) async {
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
