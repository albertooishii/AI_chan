class FakeGoogleSignInAdapter {
  Future<Map<String, dynamic>> signIn({List<String> scopes = const []}) async {
    return {'access_token': 'atk_android', 'id_token': 'id_android', 'scope': scopes.join(' ')};
  }
}
