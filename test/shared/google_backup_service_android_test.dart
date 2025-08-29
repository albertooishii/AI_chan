import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_google_sign_in_adapter.dart';

void main() {
  test('Android linking uses google_sign_in path and returns tokens', () async {
    final svc = GoogleBackupService(accessToken: null);
    final fakeAdapter = FakeGoogleSignInAdapter();

    final tokenMap = await svc.linkAccount(forceUseGoogleSignIn: true, signInAdapterOverride: fakeAdapter);

    expect(tokenMap, isNotNull);
    expect(tokenMap['access_token'], 'atk_android');
    expect(tokenMap['id_token'], 'id_android');
  });
}
