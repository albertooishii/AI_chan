/// Utilidades para agrupar y detectar proveedores de modelos.
class ModelUtils {
  /// Detecta el proveedor a partir del id de modelo usando heurísticas.
  static String detectProvider(String modelId) {
    final m = modelId.toLowerCase();
    if (m.contains('gemini') || m.contains('imagen-')) return 'Google';
    if (m.startsWith('grok-') || m.contains('grok')) return 'Grok';
    if (m.startsWith('gpt-')) return 'OpenAI';
    return 'Other';
  }

  /// Agrupa una lista de modelos por proveedor. Devuelve un mapa proveedor->[modelIds]
  static Map<String, List<String>> groupModels(
    List<String> models, {
    bool preserveOrder = true,
  }) {
    final Map<String, List<String>> out = {};
    for (final m in models) {
      final p = detectProvider(m);
      out.putIfAbsent(p, () => []).add(m);
    }
    // Por defecto preservamos el orden en que los providers devolvieron sus modelos.
    // Si preserveOrder == false, ordenamos internamente las listas alfabéticamente.
    if (!preserveOrder) {
      for (final k in out.keys) {
        out[k]!.sort();
      }
    }
    return out;
  }

  /// Orden preferido de aparición en UI.
  static List<String> preferredOrder() => ['Google', 'Grok', 'OpenAI'];
}
