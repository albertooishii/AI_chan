import 'package:flutter/material.dart';
import 'dart:async';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';

/// Call UI Controller - Manages UI state for call interface
class CallUIController extends ChangeNotifier with UIStateManagementMixin {
  CallUIController();

  // Core state
  String _currentSubtitle = '';
  bool _subtitlesEnabled = true;
  bool _subtitleDebug = true;
  int _subtitleLagMs = 1000;
  int _lastLoggedSubtitleChars = 0;
  Timer? _subtitleRevealTimer;
  String _fullSubtitleText = '';
  int _revealedChars = 0;
  bool _showCallControls = true;
  bool _showDebugInfo = false;
  double _callProgress = 0.0;
  String _callStatus = 'Idle';

  // Getters
  String get currentSubtitle => _currentSubtitle;
  bool get subtitlesEnabled => _subtitlesEnabled;
  bool get subtitleDebug => _subtitleDebug;
  bool get showCallControls => _showCallControls;
  bool get showDebugInfo => _showDebugInfo;
  double get callProgress => _callProgress;
  String get callStatus => _callStatus;
  int get subtitleLagMs => _subtitleLagMs;

  /// Update subtitle with optional animation
  void updateSubtitle(final String text, {final bool immediate = false}) {
    if (!_subtitlesEnabled) return;
    executeSyncWithNotification(
      operation: () {
        _fullSubtitleText = text;
        _revealedChars = 0;
        _subtitleRevealTimer?.cancel();

        if (immediate || _subtitleLagMs <= 0) {
          _currentSubtitle = text;
          _revealedChars = text.length;
        } else {
          _startSubtitleReveal();
        }
        _logSubtitleUpdate(text);
      },
    );
  }

  /// Clear subtitle and cancel reveal timer
  void clearSubtitle() => executeSyncWithNotification(
    operation: () {
      _subtitleRevealTimer?.cancel();
      _currentSubtitle = '';
      _fullSubtitleText = '';
      _revealedChars = 0;
    },
  );

  /// Configure subtitle settings
  void configureSubtitles({
    final bool? enabled,
    final bool? debug,
    final int? lagMs,
  }) {
    executeSyncWithNotification(
      operation: () {
        if (enabled != null) _subtitlesEnabled = enabled;
        if (debug != null) _subtitleDebug = debug;
        if (lagMs != null) _subtitleLagMs = lagMs;
      },
    );
  }

  /// Update UI state
  void updateCallProgress(final double progress) => executeSyncWithNotification(
    operation: () => _callProgress = progress.clamp(0.0, 1.0),
  );

  void updateCallStatus(final String status) => executeSyncWithNotification(
    operation: () {
      _callStatus = status;
      if (_subtitleDebug) debugPrint('📞 [CALL] Status: $status');
    },
  );

  void toggleCallControls() => executeSyncWithNotification(
    operation: () => _showCallControls = !_showCallControls,
  );

  void toggleDebugInfo() => executeSyncWithNotification(
    operation: () => _showDebugInfo = !_showDebugInfo,
  );

  void setCallControlsVisibility(final bool visible) =>
      executeSyncWithNotification(operation: () => _showCallControls = visible);

  void reset() {
    executeSyncWithNotification(
      operation: () {
        _subtitleRevealTimer?.cancel();
        _currentSubtitle = '';
        _fullSubtitleText = '';
        _revealedChars = 0;
        _lastLoggedSubtitleChars = 0;
        _callProgress = 0.0;
        _callStatus = 'Idle';
      },
    );
  }

  // Private helpers
  void _startSubtitleReveal() {
    const revealInterval = Duration(milliseconds: 50);
    _subtitleRevealTimer = Timer.periodic(revealInterval, (final timer) {
      if (_revealedChars >= _fullSubtitleText.length) {
        timer.cancel();
        return;
      }
      _revealedChars++;
      _currentSubtitle = _fullSubtitleText.substring(0, _revealedChars);
      notifyListeners();
    });
  }

  void _logSubtitleUpdate(final String text) {
    if (!_subtitleDebug) return;
    final currentChars = text.length;
    if (currentChars != _lastLoggedSubtitleChars) {
      debugPrint(
        '🎬 [UI] Subtitle updated: ${text.substring(0, (currentChars > 50) ? 50 : currentChars)}${currentChars > 50 ? '...' : ''}',
      );
      _lastLoggedSubtitleChars = currentChars;
    }
  }

  Map<String, dynamic> get debugInfo => {
    'subtitlesEnabled': _subtitlesEnabled,
    'currentSubtitleLength': _currentSubtitle.length,
    'revealProgress': _fullSubtitleText.isEmpty
        ? 0.0
        : _revealedChars / _fullSubtitleText.length,
    'callProgress': _callProgress,
    'callStatus': _callStatus,
    'showCallControls': _showCallControls,
    'showDebugInfo': _showDebugInfo,
    'subtitleLagMs': _subtitleLagMs,
  };

  @override
  void dispose() {
    _subtitleRevealTimer?.cancel();
    super.dispose();
  }
}
