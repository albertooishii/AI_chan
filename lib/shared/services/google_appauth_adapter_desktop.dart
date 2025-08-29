import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';

/// A lightweight AppAuth-like adapter for desktop platforms that implements
/// the PKCE authorization-code flow using the system browser and a loopback
/// redirect. This avoids relying on the flutter_appauth platform channel which
/// may not be available in some desktop build environments.
class GoogleAppAuthAdapter {
  final List<String> scopes;
  final String clientId;
  final String? redirectUri;

  /// Last constructed authorization URL (for UI fallback copy/open).
  static String? lastAuthUrl;

  /// Open a URL in the system browser (platform-specific).
  static Future<void> openBrowser(String url) async {
    try {
      if (Platform.isWindows) {
        final proc = await Process.start('cmd', ['/c', 'start', url]);
        Log.d('GoogleAppAuthAdapter.openBrowser: started process pid=${proc.pid} (windows)', tag: 'GoogleAppAuth');
      } else if (Platform.isMacOS) {
        final proc = await Process.start('open', [url]);
        Log.d('GoogleAppAuthAdapter.openBrowser: started process pid=${proc.pid} (macos)', tag: 'GoogleAppAuth');
      } else {
        final proc = await Process.start('xdg-open', [url]);
        Log.d('GoogleAppAuthAdapter.openBrowser: started process pid=${proc.pid} (linux)', tag: 'GoogleAppAuth');
      }
    } catch (e) {
      Log.w('GoogleAppAuthAdapter.openBrowser failed: $e', tag: 'GoogleAppAuth');
      rethrow;
    }
  }

  GoogleAppAuthAdapter({required this.scopes, required this.clientId, this.redirectUri});

  Future<Map<String, dynamic>> signIn({List<String>? scopes}) async {
    final usedScopes = (scopes ?? this.scopes).join(' ');
    Log.d(
      'GoogleAppAuthAdapter: starting authorizeAndExchangeCode clientId length=${clientId.length}',
      tag: 'GoogleAppAuth',
    );

    // Pick redirect: prefer provided redirectUri, then Config, else loopback
    String? redirect = redirectUri;
    if (redirect == null || redirect.isEmpty) {
      try {
        final cfg = Config.get('GOOGLE_REDIRECT_URI', '').trim();
        if (cfg.isNotEmpty) redirect = cfg;
      } catch (_) {}
    }

    HttpServer? server;
    Uri authRedirect;
    if (redirect == null || redirect.isEmpty) {
      // Bind loopback
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      redirect = 'http://127.0.0.1:${server.port}/';
      Log.d('GoogleAppAuthAdapter: loopback bound on ${server.address.address}:${server.port}', tag: 'GoogleAppAuth');
    }
    authRedirect = Uri.parse(redirect);

    // PKCE: generate code verifier and code challenge
    final codeVerifier = _createCodeVerifier();
    final codeChallenge = _codeChallenge(codeVerifier);

    final state = _randomString(16);
    final authorizationEndpoint = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': authRedirect.toString(),
        'scope': usedScopes,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline', // request refresh token
        'prompt': 'consent',
      },
    );

    // Save the authorization URL so the UI can offer manual copy/open if needed.
    GoogleAppAuthAdapter.lastAuthUrl = authorizationEndpoint.toString();

    // Open system browser
    try {
      await GoogleAppAuthAdapter.openBrowser(authorizationEndpoint.toString());
    } catch (e) {
      Log.w('GoogleAppAuthAdapter: failed to open browser: $e', tag: 'GoogleAppAuth');
    }

    // Wait for code on loopback if we bound one, otherwise instruct user
    String? code;
    String? returnedState;
    try {
      if (server != null) {
        final req = await server.first.timeout(Duration(minutes: 5));
        final uri = req.uri;
        final params = uri.queryParameters;
        code = params['code'];
        returnedState = params['state'];
        // reply a friendly page
        // reply with the packaged oauth_success.html when available
        try {
          String page = await rootBundle.loadString('assets/oauth_success.html');
          final appName = (Config.get('APP_NAME', '')).toString();
          final replaced = page.replaceAll('%APP_NAME%', appName.isNotEmpty ? appName : 'AI Chan');
          req.response.statusCode = 200;
          req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
          req.response.write(replaced);
          await req.response.close();
        } catch (e) {
          // fallback simple page
          req.response.statusCode = 200;
          req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
          req.response.write(
            '<html><body><h3>Autenticación completada. Puedes cerrar esta ventana.</h3></body></html>',
          );
          await req.response.close();
        }
      } else {
        // No loopback: cannot capture code automatically
        throw StateError(
          'No loopback server available to capture authorization code; set GOOGLE_REDIRECT_URI to a custom scheme and handle it in-app.',
        );
      }
    } catch (e, st) {
      Log.e('GoogleAppAuthAdapter: AppAuth failed: $e', tag: 'GoogleAppAuth', error: e, stack: st);
      try {
        if (server != null) await server.close(force: true);
      } catch (_) {}
      throw StateError('Fallo en la autenticación con AppAuth: $e');
    }

    if (returnedState == null || returnedState != state) {
      try {
        await server.close(force: true);
      } catch (_) {}
      throw StateError('State mismatch in AppAuth response');
    }
    if (code == null || code.isEmpty) {
      try {
        await server.close(force: true);
      } catch (_) {}
      throw StateError('No authorization code returned from AppAuth');
    }

    // Exchange code for tokens via HTTP POST
    try {
      final tokenEndpoint = Uri.parse('https://oauth2.googleapis.com/token');
      final body = {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'redirect_uri': authRedirect.toString(),
        'code_verifier': codeVerifier,
      };
      // Optionally include client_secret if the OAuth client requires it
      try {
        var clientSecret = Config.get('GOOGLE_CLIENT_SECRET_DESKTOP', '').trim();
        if (clientSecret.isEmpty) {
          clientSecret = Config.get('GOOGLE_CLIENT_SECRET_WEB', '').trim();
        }
        if (clientSecret.isNotEmpty) {
          body['client_secret'] = clientSecret;
          Log.d('GoogleAppAuthAdapter: included client_secret in token request (masked)', tag: 'GoogleAppAuth');
        }
      } catch (_) {}
      final req = await HttpClient().postUrl(tokenEndpoint);
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write(
        body.keys.map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(body[k] ?? '')}').join('&'),
      );
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        Log.e('GoogleAppAuthAdapter: token exchange failed ${resp.statusCode} $respBody', tag: 'GoogleAppAuth');
        throw StateError('Token exchange failed: ${resp.statusCode}');
      }
      final map = jsonDecode(respBody) as Map<String, dynamic>;
      // Close loopback
      try {
        await server.close(force: true);
      } catch (_) {}
      return map;
    } catch (e, st) {
      Log.e('GoogleAppAuthAdapter: token exchange error: $e', tag: 'GoogleAppAuth', error: e, stack: st);
      try {
        await server.close(force: true);
      } catch (_) {}
      throw StateError('Fallo en la autenticación con AppAuth: $e');
    }
  }

  // PKCE helpers
  static String _createCodeVerifier([int length = 64]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String _randomString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
