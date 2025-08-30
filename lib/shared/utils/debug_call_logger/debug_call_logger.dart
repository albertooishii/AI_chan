// Plataforma condicional: expone debugLogCallPrompt con implementación IO o web (no-op)
export 'debug_call_logger_io.dart'
    if (dart.library.html) 'debug_call_logger_web.dart';
