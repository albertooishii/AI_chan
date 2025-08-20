import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../providers/onboarding_provider.dart';
import 'package:provider/provider.dart';

class BirthDateField extends StatelessWidget {
  const BirthDateField({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<OnboardingProvider>(context);
    return TextFormField(
      readOnly: true,
      controller: provider.birthDateController,
      style: const TextStyle(color: AppColors.primary, fontFamily: 'FiraMono'),
      decoration: InputDecoration(
        labelText: "Tu fecha de nacimiento",
        labelStyle: const TextStyle(color: AppColors.secondary),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondary),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        prefixIcon: const Icon(Icons.cake, color: AppColors.secondary),
        fillColor: Colors.black,
        filled: true,
        hintText: "Selecciona tu fecha",
        hintStyle: const TextStyle(color: AppColors.primary),
      ),
      validator: (v) => provider.userBirthday == null ? "Obligatorio" : null,
      onTap: () async {
        final now = DateTime.now();
        final minAgeDate = DateTime(now.year - 18, now.month, now.day);
        final picked = await showDatePicker(
          context: context,
          initialDate: provider.userBirthday ?? DateTime(now.year - 25),
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
        if (picked != null) provider.setUserBirthday(picked);
      },
    );
  }
}
