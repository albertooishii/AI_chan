import 'package:flutter/material.dart';
import 'package:ai_chan/shared.dart'; // All infrastructure utilities available here

typedef SynthesizeTextFn = Future<void> Function(String text, String model);

/// Show text model configuration dialog
Future<bool?> showTextModelConfigurationDialog({
  required final BuildContext context,
  final SynthesizeTextFn? synthesizeText,
  final VoidCallback? onSettingsChanged,
}) {
  final stateKey = GlobalKey<_TextModelConfigurationDialogState>();
  return showAppDialog<bool>(
    builder: (final context) => AppAlertDialog(
      title: const Text('Configuración de Modelos de Texto'),
      headerActions: [
        // Action that triggers the internal refresh logic via the state key
        IconButton(
          tooltip: 'Actualizar modelos',
          icon: const Icon(Icons.refresh, color: AppColors.primary),
          onPressed: () {
            stateKey.currentState?.refreshModels(forceRefresh: true);
          },
        ),
      ],
      content: TextModelConfigurationDialog(
        key: stateKey,
        synthesizeText: synthesizeText,
        onSettingsChanged: onSettingsChanged,
      ),
    ),
  );
}

class TextModelConfigurationDialog extends StatefulWidget {
  const TextModelConfigurationDialog({
    super.key,
    this.synthesizeText,
    this.onSettingsChanged,
  });

  final SynthesizeTextFn? synthesizeText;
  final VoidCallback? onSettingsChanged;

  @override
  State<TextModelConfigurationDialog> createState() =>
      _TextModelConfigurationDialogState();
}

class _TextModelConfigurationDialogState
    extends State<TextModelConfigurationDialog> {
  String _selectedProvider = ''; // Se inicializará dinámicamente
  bool _isLoading = false;
  final Map<String, List<String>> _providerModels = {};
  String? _selectedModel;
  int _totalModelsInCache = 0;
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadInitialData();
    _loadCacheInfo();
  }

  /// Load initial data with loading state
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await _loadModels();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Refresh models for current provider
  Future<void> refreshModels({final bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      // Si es forzado, limpiar caché primero
      if (forceRefresh) {
        await CacheService.clearAllModelsCache();
        Log.d('[TextModelDialog] Caché de modelos limpiado');
      }

      await _loadModels(forceRefresh: forceRefresh);
      await _loadCacheInfo(); // Actualizar información de caché
      showAppSnackBar('Modelos actualizados');
    } on Exception catch (e) {
      showAppSnackBar('Error al actualizar modelos: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final selModel = await PrefsUtils.getSelectedModelOrDefault();
      setState(() {
        _selectedModel = selModel.isEmpty ? null : selModel;
        // Detectar proveedor basado en el modelo seleccionado
        _selectedProvider = _getProviderFromModel(_selectedModel);
      });

      // Si no hay modelo seleccionado y ya tenemos modelos cargados, aplicar modelo por defecto
      if ((_selectedModel == null || _selectedModel!.isEmpty) &&
          _providerModels.isNotEmpty) {
        _applyDefaultModelForCurrentProvider();
      }
    } on Exception catch (_) {
      // Obtener el primer provider disponible dinámicamente desde el manager
      final manager = AIProviderManager.instance;
      final availableProviders = manager.getProvidersByCapability(
        AICapability.textGeneration,
      );

      setState(() {
        _selectedProvider = availableProviders.isNotEmpty
            ? availableProviders.first
            : '';
        _selectedModel = null;
      });
    }
  }

  /// Aplica el modelo por defecto para el proveedor actual
  void _applyDefaultModelForCurrentProvider() {
    final models = _providerModels[_selectedProvider] ?? [];
    if (models.isNotEmpty) {
      final defaultModel = _getDefaultModelForProvider(
        _selectedProvider,
        models,
      );
      setState(() {
        _selectedModel = defaultModel;
      });
      Log.d(
        '[TextModelDialog] Applied default model for $_selectedProvider: $defaultModel',
      );
    }
  }

  String _getProviderFromModel(final String? model) {
    if (model == null || model.isEmpty) return 'google';

    final modelLower = model.toLowerCase();
    if (modelLower.startsWith('gpt') ||
        modelLower.startsWith('o1') ||
        modelLower.contains('openai')) {
      return 'openai';
    } else if (modelLower.startsWith('gemini') ||
        modelLower.contains('google') ||
        modelLower.contains('bard')) {
      return 'google';
    } else if (modelLower.startsWith('grok') || modelLower.contains('xai')) {
      return 'xai'; // Cambiado de 'grok' a 'xai' para coincidir con la configuración YAML
    }
    return 'google'; // Default
  }

  Map<String, String> _getProviderInfo(final String provider) {
    switch (provider) {
      case 'openai':
        return {
          'name': 'OpenAI',
          'icon': 'smart_toy',
          'description': 'GPT-4, GPT-3.5, O1 y otros modelos',
        };
      case 'google':
        return {
          'name': 'Google Gemini',
          'icon': 'auto_awesome',
          'description': 'Gemini Pro, Flash y otros modelos',
        };
      case 'xai': // Cambiado de 'grok' a 'xai'
        return {
          'name': 'xAI Grok',
          'icon': 'psychology',
          'description': 'Grok-3 y variantes',
        };
      default:
        return {
          'name': 'Otros',
          'icon': 'memory',
          'description': 'Modelos adicionales',
        };
    }
  }

  /// Obtiene el modelo por defecto para un proveedor según la configuración YAML
  String _getDefaultModelForProvider(
    final String provider,
    final List<String> availableModels,
  ) {
    try {
      Log.d(
        '[TextModelDialog] Debug - Provider: $provider, Available models: $availableModels',
      );

      // Verificar si AIProviderManager está inicializado
      if (!AIProviderManager.instance.isInitialized) {
        Log.w(
          '[TextModelDialog] Debug - AIProviderManager not initialized yet, using fallback',
        );
        return availableModels.isNotEmpty ? availableModels.first : '';
      }

      // Obtener el proveedor específico desde el mapa de proveedores
      final providerMap = AIProviderManager.instance.providers;
      final aiProvider = providerMap[provider];

      if (aiProvider != null) {
        final defaultModel = aiProvider.getDefaultModel(
          AICapability.textGeneration,
        );
        Log.d(
          '[TextModelDialog] Debug - Default model from YAML: $defaultModel',
        );

        if (defaultModel != null) {
          // Si el modelo por defecto está exactamente en la lista de modelos disponibles
          if (availableModels.contains(defaultModel)) {
            Log.d('[TextModelDialog] Debug - Exact match found: $defaultModel');
            return defaultModel;
          }

          // Si el modelo por defecto no existe exactamente, buscar por prefijo
          // (ej: "gpt-4" debería coincidir con "gpt-4-turbo", "grok-4" con "grok-4-latest")
          final prefixMatch = availableModels.firstWhere(
            (final model) =>
                model.toLowerCase().startsWith(defaultModel.toLowerCase()),
            orElse: () => '',
          );
          Log.d('[TextModelDialog] Debug - Prefix match result: $prefixMatch');
          if (prefixMatch.isNotEmpty) {
            return prefixMatch;
          }
        }
      } else {
        Log.w('[TextModelDialog] Debug - AI Provider is null for: $provider');
      }

      // Fallback: usar el primer modelo disponible del proveedor
      final fallback = availableModels.isNotEmpty ? availableModels.first : '';
      Log.d('[TextModelDialog] Debug - Using fallback: $fallback');
      return fallback;
    } on Exception catch (e) {
      Log.w(
        '[TextModelDialog] Error getting default model for provider $provider: $e',
      );
      return availableModels.isNotEmpty ? availableModels.first : '';
    }
  }

  Future<void> _loadModels({final bool forceRefresh = false}) async {
    try {
      _providerModels.clear();

      // Si no es forzado, intentar cargar desde caché primero
      if (!forceRefresh) {
        final hasCache = await _loadModelsFromCache();
        if (hasCache) {
          Log.d('[TextModelDialog] Modelos cargados desde caché');
          // Aplicar modelo por defecto si no hay ninguno seleccionado
          if (_selectedModel == null || _selectedModel!.isEmpty) {
            _applyDefaultModelForCurrentProvider();
          }
          return;
        }
      }

      // Cargar modelos desde API
      Log.d('[TextModelDialog] Cargando modelos desde API...');

      // Get all available models from all providers (same logic as ChatApplicationService)
      final allModels = <String>[];

      // Get models for text generation capability from all providers
      final textModels = await AIProviderManager.instance.getAvailableModels(
        AICapability.textGeneration,
      );
      allModels.addAll(textModels);

      // Get models for image generation capability from all providers
      final imageModels = await AIProviderManager.instance.getAvailableModels(
        AICapability.imageGeneration,
      );
      allModels.addAll(imageModels);

      // Remove duplicates
      final uniqueModels = allModels.toSet().toList();

      // Group models by provider
      for (final model in uniqueModels) {
        final provider = _getProviderFromModel(model);
        _providerModels.putIfAbsent(provider, () => []);
        _providerModels[provider]!.add(model);
      }

      // Note: Respecting the order provided by each provider
      // OpenAI provider sorts models with b.compareTo(a) (newest first)
      // Google and other providers may have their own ordering logic

      // Guardar en caché
      await _saveModelsToCache();

      // Aplicar modelo por defecto si no hay ninguno seleccionado
      if (_selectedModel == null || _selectedModel!.isEmpty) {
        _applyDefaultModelForCurrentProvider();
      }
    } on Exception catch (e) {
      Log.w('[TextModelDialog] Error loading models: $e');
      // Fallback dinámico: obtener modelos de los providers disponibles
      _providerModels.clear();

      final manager = AIProviderManager.instance;
      final availableProviders = manager.getProvidersByCapability(
        AICapability.textGeneration,
      );

      for (final providerId in availableProviders) {
        try {
          final provider = manager.providers[providerId];
          if (provider != null) {
            final models = await provider.getAvailableModelsForCapability(
              AICapability.textGeneration,
            );
            if (models.isNotEmpty) {
              _providerModels[providerId] = models;
            }
          }
        } on Exception catch (providerError) {
          Log.w(
            '[TextModelDialog] Error loading models from $providerId: $providerError',
          );
        }
      }

      // Aplicar modelo por defecto también en el fallback
      if (_selectedModel == null || _selectedModel!.isEmpty) {
        _applyDefaultModelForCurrentProvider();
      }
    }
  }

  /// Carga modelos desde caché
  Future<bool> _loadModelsFromCache() async {
    try {
      final manager = AIProviderManager.instance;
      final providers = manager.getProvidersByCapability(
        AICapability.textGeneration,
      );
      bool hasAnyCache = false;

      for (final provider in providers) {
        final cachedModels = await CacheService.getCachedModels(
          provider: provider,
        );
        if (cachedModels != null && cachedModels.isNotEmpty) {
          _providerModels[provider] = cachedModels;
          hasAnyCache = true;
        }
      }

      // Actualizar información de caché
      await _loadCacheInfo();

      return hasAnyCache;
    } on Exception catch (e) {
      Log.w('[TextModelDialog] Error loading models from cache: $e');
      return false;
    }
  }

  /// Guarda modelos en caché
  Future<void> _saveModelsToCache() async {
    try {
      for (final entry in _providerModels.entries) {
        await CacheService.saveModelsToCache(
          provider: entry.key,
          models: entry.value,
        );
      }
      Log.d('[TextModelDialog] Modelos guardados en caché');
      await _loadCacheInfo(); // Actualizar información de caché
    } on Exception catch (e) {
      Log.w('[TextModelDialog] Error saving models to cache: $e');
    }
  }

  /// Carga información sobre el caché de modelos
  Future<void> _loadCacheInfo() async {
    try {
      int total = 0;
      int cacheSize = 0;
      final manager = AIProviderManager.instance;
      final providers = manager.getProvidersByCapability(
        AICapability.textGeneration,
      );

      for (final provider in providers) {
        final cachedModels = await CacheService.getCachedModels(
          provider: provider,
        );
        if (cachedModels != null) {
          total += cachedModels.length;
          // Estimate cache size (simple estimation)
          cacheSize += cachedModels.join().length;
        }
      }

      setState(() {
        _totalModelsInCache = total;
        _cacheSize = cacheSize;
      });
    } on Exception catch (e) {
      Log.w('[TextModelDialog] Error loading cache info: $e');
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showAppDialog<bool>(
      builder: (final context) => AlertDialog(
        title: const Text('Limpiar Caché'),
        content: Text(
          '¿Eliminar ${CacheService.formatCacheSize(_cacheSize)} de modelos en caché?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Limpiar caché del sistema
      await CacheService.clearAllModelsCache();

      // Limpiar las listas locales inmediatamente para mostrar UI vacía
      setState(() {
        _providerModels.clear();
        _totalModelsInCache = 0;
        _cacheSize = 0;
        // NO mostrar spinner - solo limpiar
      });

      if (mounted) {
        showAppSnackBar(
          'Caché de modelos limpiado exitosamente',
          preferRootMessenger: true,
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      if (_selectedModel != null) {
        await PrefsUtils.setSelectedModel(_selectedModel!);
      }
    } on Exception catch (e) {
      Log.w('[TextModelDialog] Error saving settings: $e');
    }
  }

  IconData _getProviderIcon(final String provider) {
    switch (provider) {
      case 'openai':
        return Icons.smart_toy;
      case 'google':
        return Icons.auto_awesome;
      case 'xai': // Cambiado de 'grok' a 'xai'
        return Icons.psychology;
      default:
        return Icons.memory;
    }
  }

  @override
  Widget build(final BuildContext context) {
    final content = Container(
      width: 400,
      height: 500,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider Selection
          const Text(
            'Proveedor:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),

          // Provider List
          ..._providerModels.keys.map((final provider) {
            final info = _getProviderInfo(provider);
            final models = _providerModels[provider] ?? [];

            return Column(
              children: [
                ListTile(
                  leading: _selectedProvider == provider
                      ? const Icon(
                          Icons.radio_button_checked,
                          color: AppColors.secondary,
                        )
                      : const Icon(
                          Icons.radio_button_unchecked,
                          color: AppColors.primary,
                        ),
                  title: Text(
                    info['name']!,
                    style: const TextStyle(color: AppColors.primary),
                  ),
                  subtitle: Text(
                    models.isEmpty
                        ? 'No disponible'
                        : '${models.length} modelos disponibles',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: Icon(
                    _getProviderIcon(provider),
                    color: AppColors.secondary,
                    size: 20,
                  ),
                  enabled: models.isNotEmpty,
                  onTap: models.isNotEmpty
                      ? () async {
                          setState(() {
                            _selectedProvider = provider;
                            // Seleccionar automáticamente el modelo por defecto del proveedor
                            _selectedModel = _getDefaultModelForProvider(
                              provider,
                              models,
                            );
                          });
                          await _saveSettings();
                          if (widget.onSettingsChanged != null) {
                            widget.onSettingsChanged!.call();
                          }
                          showAppSnackBar(
                            'Proveedor cambiado a ${info['name']}',
                          );
                        }
                      : null,
                ),
                const SizedBox(height: 4),
              ],
            );
          }),

          const SizedBox(height: 16),
          const Divider(color: AppColors.secondary),
          const SizedBox(height: 12),

          // Models list
          const Text(
            'Modelos:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.secondary,
                    ),
                  )
                : _buildModelList(),
          ),

          const SizedBox(height: 12),

          // Info section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.secondary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Proveedor: ${_getProviderInfo(_selectedProvider)['name']}${_selectedModel != null ? ' ($_selectedModel)' : ''}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _getProviderInfo(_selectedProvider)['description']!,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                if (_totalModelsInCache > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.cached,
                            color: AppColors.secondary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Caché: $_totalModelsInCache modelos almacenados',
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      // Botón limpiar caché en la misma línea
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Limpiar'),
                        onPressed: _cacheSize > 0 ? _clearCache : null,
                      ),
                    ],
                  ),
                ] else ...[
                  // Si no hay caché, mostrar el botón solo
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Limpiar'),
                      onPressed: _cacheSize > 0 ? _clearCache : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return content;
  }

  Widget _buildModelList() {
    final models = _providerModels[_selectedProvider] ?? [];

    if (models.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
            const SizedBox(height: 16),
            Text(
              'No hay modelos disponibles\npara ${_getProviderInfo(_selectedProvider)['name']}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => refreshModels(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: models.length,
      itemBuilder: (final context, final index) {
        final model = models[index];
        final isSelected = _selectedModel == model;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: isSelected
              ? const Icon(
                  Icons.radio_button_checked,
                  size: 20,
                  color: AppColors.secondary,
                )
              : const Icon(
                  Icons.radio_button_unchecked,
                  size: 20,
                  color: AppColors.primary,
                ),
          title: Text(model, style: const TextStyle(color: AppColors.primary)),
          subtitle: Text(
            _getModelDescription(model),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Test button (if synthesizeText is provided)
                if (widget.synthesizeText != null)
                  IconButton(
                    icon: const Icon(
                      Icons.psychology,
                      color: AppColors.secondary,
                    ),
                    tooltip: 'Probar modelo',
                    onPressed: () async {
                      final testText =
                          'Hola, soy tu asistente usando el modelo $model';
                      showAppSnackBar('Probando modelo $model...');
                      try {
                        await widget.synthesizeText!(testText, model);
                        showAppSnackBar('Prueba completada con $model');
                      } on Exception catch (e) {
                        showAppSnackBar(
                          'Error probando modelo: $e',
                          isError: true,
                        );
                      }
                    },
                  ),

                // Select button
                IconButton(
                  icon: isSelected
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.secondary,
                        )
                      : const Icon(
                          Icons.circle_outlined,
                          color: AppColors.primary,
                        ),
                  tooltip: 'Seleccionar modelo',
                  onPressed: () async {
                    setState(() => _selectedModel = model);
                    try {
                      await PrefsUtils.setSelectedModel(model);
                      if (widget.onSettingsChanged != null) {
                        widget.onSettingsChanged!.call();
                      }
                      showAppSnackBar('Modelo seleccionado: $model');
                    } on Exception catch (e) {
                      showAppSnackBar(
                        'Error guardando el modelo seleccionado: $e',
                        isError: true,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          onTap: () async {
            setState(() => _selectedModel = model);
            try {
              await PrefsUtils.setSelectedModel(model);
              if (widget.onSettingsChanged != null) {
                widget.onSettingsChanged!.call();
              }
              showAppSnackBar('Modelo seleccionado: $model');
            } on Exception catch (e) {
              showAppSnackBar(
                'Error guardando el modelo seleccionado: $e',
                isError: true,
              );
            }
          },
        );
      },
    );
  }

  String _getModelDescription(final String model) {
    final modelLower = model.toLowerCase();

    // Descripción genérica basada en patrones comunes
    if (modelLower.contains('turbo')) {
      return 'Modelo Turbo • Rápido y eficiente';
    } else if (modelLower.contains('mini')) {
      return 'Modelo Mini • Optimizado para velocidad';
    } else if (modelLower.contains('preview')) {
      return 'Modelo Preview • Capacidades avanzadas';
    } else if (modelLower.contains('pro')) {
      return 'Modelo Pro • Rendimiento superior';
    } else if (modelLower.contains('flash')) {
      return 'Modelo Flash • Ultra rápido';
    } else if (modelLower.contains('vision')) {
      return 'Modelo Vision • Procesamiento visual';
    } else if (modelLower.contains('realtime')) {
      return 'Modelo Realtime • Conversación en tiempo real';
    }

    // Descripción por defecto con el nombre del modelo
    return '${model.split('-').first.toUpperCase()} • Modelo de IA';
  }
}
