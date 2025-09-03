import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/shared/constants/female_names.dart';

/// Widget reutilizable para autocompletar nombres femeninos
class FemaleNameAutocomplete extends StatelessWidget {
  final String? selectedName;
  final String? countryCode; // Para filtrar nombres por país
  final void Function(String name) onNameSelected;
  final void Function(String name)? onChanged;
  final String labelText;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final TextEditingController? controller;

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

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      key: ValueKey('name-autocomplete-${countryCode ?? 'none'}'),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          // Sugerencias base por país si no hay texto
          final base = FemaleNamesRepo.forCountry(countryCode);
          return base.take(20);
        }
        final source = FemaleNamesRepo.forCountry(countryCode);
        return source
            .where(
              (option) => option.toLowerCase().contains(
                textEditingValue.text.toLowerCase(),
              ),
            )
            .take(50);
      },
      fieldViewBuilder:
          (context, fieldController, focusNode, onEditingComplete) {
            // Usar el controller proporcionado o el interno
            final effectiveController = controller ?? fieldController;

            // Sincronizar el valor inicial solo si está vacío
            if (effectiveController.text.isEmpty &&
                selectedName?.isNotEmpty == true) {
              effectiveController.text = selectedName!;
            }

            return TextFormField(
              controller: effectiveController,
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
      onSelected: (selection) {
        onNameSelected(selection);
      },
    );
  }
}
