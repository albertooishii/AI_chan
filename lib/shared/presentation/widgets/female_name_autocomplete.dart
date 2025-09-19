import 'package:flutter/material.dart';
import 'package:ai_chan/shared.dart';

/// Widget reutilizable para autocompletar nombres femeninos
class FemaleNameAutocomplete extends StatelessWidget {
  const FemaleNameAutocomplete({
    super.key,
    required this.selectedName,
    this.countryCode,
    required this.onNameSelected,
    this.onChanged,
    required this.labelText,
    this.prefixIcon,
    this.validator,
    this.controller,
  });
  final String? selectedName;
  final String? countryCode; // Para filtrar nombres por país
  final void Function(String name) onNameSelected;
  final void Function(String name)? onChanged;
  final String labelText;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final TextEditingController? controller;

  @override
  Widget build(final BuildContext context) {
    return Autocomplete<String>(
      key: ValueKey('name-autocomplete-${countryCode ?? 'none'}'),
      optionsBuilder: (final TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          // Sugerencias base por país si no hay texto
          final base = FemaleNamesRepo.forCountry(countryCode);
          return base.take(20);
        }
        final source = FemaleNamesRepo.forCountry(countryCode);
        return source
            .where(
              (final option) => option.toLowerCase().contains(
                textEditingValue.text.toLowerCase(),
              ),
            )
            .take(50);
      },
      fieldViewBuilder:
          (
            final context,
            final fieldController,
            final focusNode,
            final onEditingComplete,
          ) {
            // Siempre usar el controlador interno de Autocomplete (fieldController)
            // para que Autocomplete pueda escuchar los cambios y mostrar sugerencias.
            // Inicializar el texto interno a partir del controller externo o selectedName.
            if (fieldController.text.isEmpty) {
              if (controller != null && controller!.text.isNotEmpty) {
                fieldController.text = controller!.text;
              } else if (selectedName?.isNotEmpty == true) {
                fieldController.text = selectedName!;
              }
            }

            return TextFormField(
              controller: fieldController,
              focusNode: focusNode,
              onChanged: onChanged,
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
                fillColor: Colors.black,
                filled: true,
              ),
              validator: validator,
              onEditingComplete: onEditingComplete,
            );
          },
      onSelected: (final selection) {
        onNameSelected(selection);
      },
    );
  }
}
