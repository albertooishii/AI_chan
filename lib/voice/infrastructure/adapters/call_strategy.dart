/// Lightweight helper to decide call strategy (realtime vs buffered) per provider.
///
/// Purpose: make the separation explicit and testable without touching the
/// existing realtime clients. Keep logic conservative: only 'openai' maps to
/// realtime; others (google/gemini) use buffered utterance flow.
enum CallMode { realtime, buffered }

CallMode callModeForProvider(String provider) {
  final p = provider.trim().toLowerCase();
  if (p == 'openai') return CallMode.realtime;
  return CallMode.buffered;
}
