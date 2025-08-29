import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';

/// A presentation-only birth date field. The parent is responsible for
/// providing a [controller], the current [userBirthday] value and an
/// [onBirthdayChanged] callback which will be called when the user picks a
/// date. This keeps the widget free of Provider dependencies.
class BirthDateField extends StatelessWidget {
  final TextEditingController controller;
  final DateTime? userBirthday;
  final ValueChanged<DateTime> onBirthdayChanged;

  const BirthDateField({
    super.key,
    required this.controller,
    required this.userBirthday,
    required this.onBirthdayChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: controller,
      style: const TextStyle(color: AppColors.primary, fontFamily: 'FiraMono'),
      decoration: InputDecoration(
        labelText: "Tu fecha de nacimiento",
        labelStyle: const TextStyle(color: AppColors.secondary),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.secondary)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary, width: 2)),
        prefixIcon: const Icon(Icons.cake, color: AppColors.secondary),
        fillColor: Colors.black,
        filled: true,
        hintText: "Selecciona tu fecha",
        hintStyle: const TextStyle(color: AppColors.primary),
      ),
      validator: (v) => userBirthday == null ? "Obligatorio" : null,
      onTap: () async {
        final now = DateTime.now();
        final minAgeDate = DateTime(now.year - 18, now.month, now.day);
        final picked = await showDatePicker(
          context: context,
          initialDate: userBirthday ?? DateTime(now.year - 25),
          firstDate: DateTime(1950),
          lastDate: minAgeDate,
          locale: const Locale('es'),
          builder: (context, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: ColorScheme.dark(
                primary: AppColors.secondary,
                onPrimary: Colors.black,
                surface: Colors.black,
                onSurface: AppColors.primary,
              ),
              dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
            ),
            child: child!,
          ),
        );
        if (picked != null) onBirthdayChanged(picked);
      },
    );
  }
}
