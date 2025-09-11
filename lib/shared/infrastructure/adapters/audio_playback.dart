import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/services.dart';
import 'package:ai_chan/shared/domain/interfaces/audio_playback_service.dart';

/// Abstraction over audio playback so production code can use the real
/// audioplayers implementation while tests inject a lightweight fake.
abstract class AudioPlayback implements AudioPlaybackService {
  @override
  Stream<void> get onPlayerComplete;
  @override
  Stream<Duration> get onDurationChanged;
  @override
  Stream<Duration> get onPositionChanged;
  @override
  Future<void> play(final dynamic source);
  @override
  Future<void> stop();
  @override
  Future<void> dispose();
  @override
  Future<void> setReleaseMode(final dynamic mode);

  /// Helper to adapt either an existing [ap.AudioPlayer] or an [AudioPlayback]
  /// instance into an [AudioPlayback]. If [candidate] is null a new real
  /// [ap.AudioPlayer] wrapped will be returned.
  static AudioPlayback adapt(final dynamic candidate) {
    if (candidate == null) return RealAudioPlayback(ap.AudioPlayer());
    if (candidate is AudioPlayback) return candidate;
    if (candidate is ap.AudioPlayer) return RealAudioPlayback(candidate);
    // Fallback: try to construct a real player
    return RealAudioPlayback(ap.AudioPlayer());
  }
}

class RealAudioPlayback implements AudioPlayback {
  RealAudioPlayback([final ap.AudioPlayer? player])
    : _player = player ?? ap.AudioPlayer();
  final ap.AudioPlayer _player;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete.map((_) {});
  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  @override
  Future<void> play(final dynamic source) async {
    // Run the playback logic in a guarded zone so asynchronous exceptions
    // coming from the native plugin (which can surface via platform
    // callbacks) are captured and don't bubble up as uncaught
    // PlatformExceptions crashing the app.
    final completer = Completer<void>();
    runZonedGuarded(
      () {
        () async {
          // audioplayers expects a Source. Allow callers to pass a file path (String),
          // Uint8List (for generated audio), an existing ap.Source, or any object that
          // can be converted to string (fallback).
          ap.Source src;
          if (source is Uint8List) {
            // Handle generated audio data directly using BytesSource
            src = ap.BytesSource(source);
          } else if (source is String) {
            // Prefer DeviceFileSource for local files. Some devices/Android versions
            // report IO errors when the plugin uses file-descriptors. As a robust
            // fallback, try reading the file bytes and play via BytesSource.
            final path = source;
            // If path points to an existing file, attempt DeviceFileSource first.
            try {
              final f = File(path);
              if (f.existsSync()) {
                try {
                  src = ap.DeviceFileSource(path);
                  await _player.play(src);
                  if (!completer.isCompleted) completer.complete();
                  return;
                } on Exception catch (e) {
                  // DeviceFileSource failed for this device; fall through to bytes option.
                  try {
                    debugPrint(
                      '[AudioPlayback] DeviceFileSource failed, will try BytesSource for $path: $e',
                    );
                  } on Exception catch (_) {}
                }

                // Try bytes fallback
                try {
                  final bytes = await f.readAsBytes();
                  final bytesSrc = ap.BytesSource(bytes);
                  await _player.play(bytesSrc);
                  if (!completer.isCompleted) completer.complete();
                  return;
                } on Exception catch (e) {
                  try {
                    debugPrint(
                      '[AudioPlayback] BytesSource fallback failed for $path: $e',
                    );
                  } on Exception catch (_) {}
                  // final fallback: try DeviceFileSource again (best-effort)
                  src = ap.DeviceFileSource(path);
                  // If both DeviceFileSource and BytesSource failed, attempt to obtain a
                  // content:// URI via platform FileProvider and play via UrlSource.
                  try {
                    final channel = const MethodChannel(
                      'ai_chan/file_provider',
                    );
                    final contentUri = await channel.invokeMethod<String>(
                      'getContentUriForFile',
                      {'path': path},
                    );
                    if (contentUri != null && contentUri.isNotEmpty) {
                      try {
                        final urlSrc = ap.UrlSource(contentUri);
                        await _player.play(urlSrc);
                        if (!completer.isCompleted) completer.complete();
                        return;
                      } on Exception catch (e) {
                        try {
                          debugPrint(
                            '[AudioPlayback] UrlSource(FileProvider) failed for $contentUri: $e',
                          );
                        } on Exception catch (_) {}
                      }
                    }
                  } on Exception catch (e) {
                    try {
                      debugPrint(
                        '[AudioPlayback] FileProvider content URI step failed for $path: $e',
                      );
                    } on Exception catch (_) {}
                  }
                }
              } else {
                // Path doesn't exist - treat as generic string and let plugin decide
                src = ap.DeviceFileSource(path);
              }
            } on Exception catch (e) {
              // If any unexpected error happens, fallback to converting to string
              // and trying DeviceFileSource.
              try {
                debugPrint(
                  '[AudioPlayback] Error preparing local file source: $e',
                );
              } on Exception catch (_) {}
              src = ap.DeviceFileSource(source.toString());
            }
          } else if (source is ap.Source) {
            src = source;
          } else {
            // Best-effort fallback: convert to string and treat as file path.
            src = ap.DeviceFileSource(source.toString());
          }

          try {
            await _player.play(src);
          } on Exception catch (e) {
            // Avoid crashing the app when the audio resource doesn't exist or the
            // platform player fails to set the source. Log a friendly message and
            // let the caller continue (UI should reflect playback failure).
            try {
              debugPrint('[AudioPlayback] play failed for source=$source: $e');
            } on Exception catch (_) {}
          }

          if (!completer.isCompleted) completer.complete();
        }();
      },
      (final error, final stack) {
        try {
          debugPrint(
            '[AudioPlayback] uncaught async error in playback zone: $error',
          );
        } on Exception catch (_) {}
        // Ensure the future completes even if an async uncaught error occurred
        // so callers awaiting the play() future don't block forever.
        try {
          if (!completer.isCompleted) completer.complete();
        } on Exception catch (_) {}
      },
    );

    return completer.future;
  }

  @override
  Future<void> stop() async => _player.stop();

  @override
  Future<void> dispose() async => _player.dispose();

  @override
  Future<void> setReleaseMode(final dynamic mode) async =>
      _player.setReleaseMode(mode);
}
