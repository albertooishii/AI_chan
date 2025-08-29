// Conditional adapter facade for google_sign_in
// Selects web implementation when compiled for the web, otherwise uses the
// IO implementation (Android/iOS). The IO implementation will throw on
// desktop platforms so callers can choose AppAuth there.

export 'google_sign_in_adapter_io.dart' if (dart.library.html) 'google_sign_in_adapter_web.dart';
