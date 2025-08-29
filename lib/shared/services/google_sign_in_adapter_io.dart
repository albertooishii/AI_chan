import 'package:google_sign_in/google_sign_in.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class GoogleSignInAdapter {
  GoogleSignInAdapter({required List<String> scopes, String? clientId, String? serverClientId}) {
    // Initialize the shared instance with optional clientId and serverClientId
    try {
      GoogleSignIn.instance.initialize(clientId: clientId, serverClientId: serverClientId);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> signIn({List<String> scopes = const []}) async {
    final dynamic signInInstance = GoogleSignIn.instance;
    try {
      // Prefer a single authenticate(scopeHint:) call when available.
      dynamic account;
      bool authenticateMissing = false;
      try {
        account = await signInInstance.authenticate(scopeHint: scopes);
      } on NoSuchMethodError catch (_) {
        // authenticate not present on this plugin build; mark and try fallbacks below
        authenticateMissing = true;
      } catch (e) {
        // If the error looks like a user cancellation, stop and surface as cancelled.
        final msg = e.toString().toLowerCase();
        if (msg.contains('cancel') ||
            msg.contains('user cancelled') ||
            msg.contains('user canceled') ||
            msg.contains('oncancel') ||
            msg.contains('oncancelled') ||
            msg.contains('getcredentialresponse') ||
            msg.contains('ime') ||
            msg.contains('chooser')) {
          throw StateError('User cancelled Google sign-in');
        }
        // Unknown error: rethrow to be handled by caller
        rethrow;
      }

      if (authenticateMissing) {
        // Try non-scope authenticate if available, otherwise try signIn(), but
        // don't chain calls if any of them fail due to user cancellation.
        try {
          account = await signInInstance.authenticate();
        } on NoSuchMethodError catch (_) {
          try {
            account = await signInInstance.signIn();
          } on NoSuchMethodError catch (nsm) {
            Log.d('GoogleSignInAdapter IO: signIn() not available on this plugin build: $nsm', tag: 'GoogleSignIn');
            throw StateError('Método de inicio de sesión no disponible en este dispositivo');
          }
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('cancel') ||
              msg.contains('user cancelled') ||
              msg.contains('user canceled') ||
              msg.contains('oncancel') ||
              msg.contains('oncancelled') ||
              msg.contains('getcredentialresponse') ||
              msg.contains('ime') ||
              msg.contains('chooser')) {
            throw StateError('User cancelled Google sign-in');
          }
          rethrow;
        }
      }

      if (account == null) throw StateError('User cancelled Google sign-in');

      // Try to obtain authorization/access token for requested scopes
      try {
        final dynamic authClient = account.authorizationClient;
        if (authClient != null && scopes.isNotEmpty) {
          final dynamic authorization = await authClient.authorizationForScopes(scopes);
          if (authorization != null) {
            return {'access_token': authorization.accessToken, 'id_token': null, 'scope': scopes.join(' ')};
          }
        }
      } catch (_) {}

      // Last resort: use legacy authentication getter if available
      try {
        final dynamic auth = await account.authentication;
        return {'access_token': auth.accessToken, 'id_token': auth.idToken, 'scope': scopes.join(' ')};
      } catch (e) {
        Log.w('GoogleSignInAdapter IO: failed to obtain tokens from account.authentication: $e', tag: 'GoogleSignIn');
        throw StateError('No se pudieron obtener tokens de autenticación');
      }
    } on NoSuchMethodError catch (nsm) {
      // Defensive: map any NoSuchMethodError to a friendly StateError
      Log.d('GoogleSignInAdapter IO: NoSuchMethodError: $nsm', tag: 'GoogleSignIn');
      throw StateError('Integración de Google Sign-In no disponible en este dispositivo');
    } catch (e, st) {
      Log.e('GoogleSignInAdapter IO: unexpected sign-in error: $e', tag: 'GoogleSignIn', error: e, stack: st);
      // Propagate as StateError to keep UI messages user-friendly
      throw StateError(e.toString());
    }
  }
}
