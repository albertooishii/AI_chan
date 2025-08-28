import 'dart:convert';
import 'dart:io';

import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('device flow and resumable upload flow (mocked)', () async {
    // Mock client that responds to device code, token polling, init resumable and put
    final client = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('/device/code')) {
        return http.Response(
          jsonEncode({
            'device_code': 'dev123',
            'user_code': 'USER-CODE',
            'verification_url': 'https://example.com/device',
            'interval': 1,
          }),
          200,
        );
      }
      if (url.contains('/token')) {
        // return token on first poll
        return http.Response(
          jsonEncode({'access_token': 'atk', 'refresh_token': 'rtk', 'expires_in': 3600, 'token_type': 'Bearer'}),
          200,
        );
      }
      if (url.contains('/upload') &&
          request.method == 'POST' &&
          request.headers['X-Upload-Content-Type'] == 'application/zip') {
        // initiation returns location header
        return http.Response('{}', 200, headers: {'location': 'https://upload.example.com/session/abc'});
      }
      if (url.contains('upload.example.com') && request.method == 'PUT') {
        return http.Response(jsonEncode({'id': 'file123'}), 200);
      }
      return http.Response('not found', 404);
    });

    final service = GoogleBackupService(accessToken: null, httpClient: client);

    final start = await service.startDeviceAuthorization(clientId: 'cid');
    expect(start['device_code'], 'dev123');

    final token = await service.pollForDeviceToken(clientId: 'cid', deviceCode: 'dev123', interval: 1, maxAttempts: 2);
    expect(token['access_token'], 'atk');

    // Create a temp zip file
    final tmp = Directory.systemTemp.createTempSync('ai_chan_test_');
    final f = File('${tmp.path}/test.zip');
    await f.writeAsBytes([0, 1, 2, 3, 4]);

    // create a new service instance that holds the access token
    final serviceWithToken = GoogleBackupService(accessToken: token['access_token'] as String?, httpClient: client);
    final id = await serviceWithToken.uploadBackupResumable(f);
    expect(id, 'file123');

    tmp.deleteSync(recursive: true);
  });
}
