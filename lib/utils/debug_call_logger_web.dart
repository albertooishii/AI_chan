import 'package:flutter/foundation.dart';

/// No-op en web para evitar errores de IO.
Future<void> debugLogCallPrompt(String fileBaseName, Map<String, dynamic> jsonObj) async {
  if (kReleaseMode) return;
  // No escribir en web; podríamos usar console.log si se desea.
}
