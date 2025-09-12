/// 🎵 Estados del reproductor de audio centralizado
enum AudioPlaybackState {
  idle('Inactivo', '💤'),
  loading('Cargando', '🔄'),
  playing('Reproduciendo', '▶️'),
  paused('Pausado', '⏸️'),
  stopped('Detenido', '⏹️'),
  completed('Completado', '✅'),
  error('Error', '❌');

  const AudioPlaybackState(this.displayName, this.emoji);

  final String displayName;
  final String emoji;

  @override
  String toString() => '$displayName $emoji';
}
