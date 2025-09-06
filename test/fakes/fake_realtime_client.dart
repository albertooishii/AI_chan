import 'dart:typed_data';

/// Fake minimal que emite un texto y un audio chunk cuando se le llama.
class FakeRealtimeClient {
  FakeRealtimeClient({this.onText, this.onAudio, this.onCompleted});
  final void Function(String)? onText;
  final void Function(Uint8List)? onAudio;
  final void Function()? onCompleted;

  Future<void> connect({
    required final String systemPrompt,
    final String voice = 'default',
  }) async {
    // no-op
  }

  Future<void> sendUserAudio(final List<int> bytes) async {
    // Simula transcripcion -> respuesta
    await Future.delayed(const Duration(milliseconds: 20));
    onText?.call('Hola desde FakeRealtime');
    onAudio?.call(Uint8List.fromList([1, 2, 3, 4]));
    onCompleted?.call();
  }

  Future<void> close() async {}
}
