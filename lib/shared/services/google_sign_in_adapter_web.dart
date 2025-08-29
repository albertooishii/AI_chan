import 'package:google_sign_in/google_sign_in.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class GoogleSignInAdapter {
  GoogleSignInAdapter({required List<String> scopes, String? clientId, String? serverClientId}) {
    try {
      GoogleSignIn.instance.initialize(clientId: clientId, serverClientId: serverClientId);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> signIn({List<String> scopes = const []}) async {
    final dynamic signInInstance = GoogleSignIn.instance;
    try {
      dynamic account;
      try {
        account = await signInInstance.authenticate(scopeHint: scopes);
      } catch (_) {
        try {
          account = await signInInstance.signIn();
        } catch (e) {
          Log.d('GoogleSignInAdapter Web: signIn/authenticate failed: $e', tag: 'GoogleSignIn');
          rethrow;
        }
      }

      if (account == null) throw StateError('User cancelled Google sign-in');

      try {
        final dynamic authClient = account.authorizationClient;
        if (authClient != null && scopes.isNotEmpty) {
          final dynamic authorization = await authClient.authorizationForScopes(scopes);
          if (authorization != null) {
            return {'access_token': authorization.accessToken, 'id_token': null, 'scope': scopes.join(' ')};
          }
        }
      } catch (_) {}

      try {
        final dynamic auth = await account.authentication;
        return {'access_token': auth.accessToken, 'id_token': auth.idToken, 'scope': scopes.join(' ')};
      } catch (e) {
        Log.w('GoogleSignInAdapter Web: failed to obtain tokens from account.authentication: $e', tag: 'GoogleSignIn');
        throw StateError('No se pudieron obtener tokens de autenticación web');
      }
    } on NoSuchMethodError catch (nsm) {
      Log.d('GoogleSignInAdapter Web: NoSuchMethodError: $nsm', tag: 'GoogleSignIn');
      throw StateError('Integración de Google Sign-In no disponible en este navegador/versión');
    } catch (e, st) {
      Log.e('GoogleSignInAdapter Web: unexpected sign-in error: $e', tag: 'GoogleSignIn', error: e, stack: st);
      throw StateError(e.toString());
    }
  }
}
