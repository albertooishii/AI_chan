import 'dart:io';
import 'package:ai_chan/shared.dart' as audio_utils;
import 'package:flutter/foundation.dart';

/// Utility helpers to convert audio using ffmpeg when available.
class AudioConversion {
  static Future<bool> ffmpegAvailable() async {
    try {
      final ver = await Process.run('ffmpeg', ['-version']);
      return ver.exitCode == 0;
    } on Exception catch (_) {
      return false;
    }
  }

  static Future<File?> convertFileToFormat(
    final File src,
    final String format, {
    final List<String>? extraArgs,
  }) async {
    if (!await ffmpegAvailable()) return null;
    try {
      // Use the local audio dir for temporary conversion outputs so that
      // converted files live on the same filesystem as persisted audio and
      // avoid EXDEV when callers move/rename them into the audio directory.
      final tmpDir = await audio_utils.getLocalAudioDir();
      final outPath =
          '${tmpDir.path}/${src.path.split('/').last}.converted.$format';
      final args = <String>['-y', '-i', src.path];
      if (extraArgs != null) args.addAll(extraArgs);
      args.add(outPath);
      final proc = await Process.run('ffmpeg', args);
      if (proc.exitCode == 0) {
        final outFile = File(outPath);
        if (outFile.existsSync()) return outFile;
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioConversion] convertFileToFormat exception: $e');
      }
    }
    return null;
  }

  static Future<Uint8List?> convertBytesToFormat(
    final Uint8List inputBytes,
    final String format, {
    final List<String>? extraArgs,
  }) async {
    if (!await ffmpegAvailable()) return null;
    try {
      final tmpDir = await audio_utils.getLocalAudioDir();
      final inPath =
          '${tmpDir.path}/tts_in_${DateTime.now().millisecondsSinceEpoch}.bin';
      final outPath =
          '${tmpDir.path}/tts_out_${DateTime.now().millisecondsSinceEpoch}.$format';
      final inFile = File(inPath);
      await inFile.writeAsBytes(inputBytes);
      final args = <String>['-y', '-i', inFile.path];
      if (extraArgs != null) args.addAll(extraArgs);
      args.add(outPath);
      final proc = await Process.run('ffmpeg', args);
      if (proc.exitCode == 0) {
        final outFile = File(outPath);
        if (outFile.existsSync()) {
          final res = await outFile.readAsBytes();
          try {
            await inFile.delete();
            await outFile.delete();
          } on Exception catch (_) {}
          return res;
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioConversion] convertBytesToFormat exception: $e');
      }
    }
    return null;
  }

  static Future<File?> convertToWavIfPossible(final File src) async {
    return await convertFileToFormat(
      src,
      'wav',
      extraArgs: ['-ac', '1', '-ar', '16000', '-acodec', 'pcm_s16le'],
    );
  }

  static Future<File?> convertToMp3IfPossible(final File src) async {
    return await convertFileToFormat(
      src,
      'mp3',
      extraArgs: [
        '-ac',
        '1',
        '-ar',
        '16000',
        '-b:a',
        '64k',
        '-codec:a',
        'libmp3lame',
      ],
    );
  }
}
