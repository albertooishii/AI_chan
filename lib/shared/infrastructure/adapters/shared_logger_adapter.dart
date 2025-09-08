import 'package:ai_chan/shared/domain/interfaces/i_shared_logger.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Infrastructure adapter that implements shared logger interface
/// by delegating to existing Log utility.
class SharedLoggerAdapter implements ISharedLogger {
  @override
  void debug(final String message, {final String? tag}) {
    Log.d(message, tag: tag ?? 'SHARED');
  }

  @override
  void error(final String message, {final String? tag, final Object? error}) {
    Log.e(message, tag: tag ?? 'SHARED', error: error);
  }
}
