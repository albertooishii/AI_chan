import 'package:flutter/material.dart';
import 'package:ai_chan/shared.dart'; // Using shared exports for infrastructure
// REMOVED: Direct infrastructure imports - using shared.dart instead
// import 'package:ai_chan/shared.dart';
// import 'package:ai_chan/shared/infrastructure/utils/string_utils.dart';

/// Widget reutilizable para autocompletar países
class CountryAutocomplete extends StatelessWidget {
  // códigos ISO2 preferidos al inicio

  const CountryAutocomplete({
    super.key,
    required this.selectedCountryCode,
    required this.onCountrySelected,
    required this.labelText,
    this.helperText,
    this.prefixIcon,
    this.validator,
    this.preferredCountries,
  });
  final String? selectedCountryCode;
  final void Function(String countryCode) onCountrySelected;
  final String labelText;
  final String? helperText;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final List<String>? preferredCountries;

  // Helper: auto-abrir el Autocomplete al enfocar
  void _attachAutoOpen(
    final TextEditingController controller,
    final FocusNode focusNode,
  ) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        final original = controller.text;
        controller.text = ' ';
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        Future.microtask(() {
          controller.text = original;
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        });
      }
    });
  }

  @override
  Widget build(final BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (final TextEditingValue textEditingValue) {
        final items = List<CountryItem>.from(CountriesEs.items);

        // Aplicar países preferidos si se especifican
        if (preferredCountries != null && preferredCountries!.isNotEmpty) {
          for (var i = preferredCountries!.length - 1; i >= 0; i--) {
            final iso = preferredCountries![i];
            final idx = items.indexWhere((final c) => c.iso2 == iso);
            if (idx != -1) {
              final it = items.removeAt(idx);
              items.insert(0, it);
            }
          }
        }

        final q = normalizeForSearch(textEditingValue.text.trim());
        final opts = items.map((final c) {
          final flag = LocaleUtils.flagEmojiForCountry(c.iso2);
          return '${flag.isNotEmpty ? '$flag ' : ''}${c.nameEs} (${c.iso2})';
        });
        if (q.isEmpty) return opts.take(50);
        return opts
            .where((final o) => normalizeForSearch(o).contains(q))
            .take(50);
      },
      fieldViewBuilder:
          (
            final context,
            final controller,
            final focusNode,
            final onEditingComplete,
          ) {
            // Inicializa el texto si ya hay código guardado
            final code = selectedCountryCode;
            if ((controller.text.isEmpty) && code != null && code.isNotEmpty) {
              final name = CountriesEs.codeToName[code.toUpperCase()];
              if (name != null) {
                final flag = LocaleUtils.flagEmojiForCountry(code);
                controller.text =
                    '${flag.isNotEmpty ? '$flag ' : ''}$name ($code)';
              }
            }

            // Abrir opciones al enfocar
            _attachAutoOpen(controller, focusNode);

            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(
                color: AppColors.primary,
                fontFamily: 'FiraMono',
              ),
              decoration: InputDecoration(
                labelText: labelText,
                labelStyle: const TextStyle(color: AppColors.secondary),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.secondary),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                prefixIcon: prefixIcon != null
                    ? Icon(prefixIcon, color: AppColors.secondary)
                    : null,
                helperText:
                    selectedCountryCode?.isNotEmpty == true &&
                        helperText != null
                    ? helperText
                    : (selectedCountryCode?.isNotEmpty == true
                          ? 'Idioma: ${LocaleUtils.languageNameEsForCountry(selectedCountryCode!)}'
                          : null),
                helperStyle: const TextStyle(color: AppColors.secondary),
                fillColor: Colors.black,
                filled: true,
              ),
              validator: validator,
              onEditingComplete: onEditingComplete,
            );
          },
      onSelected: (final selection) {
        // Extrae ISO2 del texto "Nombre (XX)"
        final match = RegExp(r'\(([^)]+)\)$').firstMatch(selection);
        final code = match != null ? match.group(1)! : '';
        onCountrySelected(code);
      },
    );
  }
}
