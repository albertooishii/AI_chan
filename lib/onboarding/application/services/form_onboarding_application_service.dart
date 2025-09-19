import 'package:ai_chan/shared.dart';
import 'package:ai_chan/onboarding.dart';

/// Result objects for DDD pattern compliance
class FormValidationResult {
  const FormValidationResult({
    required this.isValid,
    this.fieldErrors = const {},
    this.generalError,
  });

  factory FormValidationResult.success() =>
      const FormValidationResult(isValid: true);

  factory FormValidationResult.failure({
    final Map<String, String>? fieldErrors,
    final String? generalError,
  }) => FormValidationResult(
    isValid: false,
    fieldErrors: fieldErrors ?? {},
    generalError: generalError,
  );
  final bool isValid;
  final Map<String, String> fieldErrors;
  final String? generalError;
}

class DataImportResult {
  const DataImportResult({
    required this.success,
    this.importedData,
    this.formPreset,
    this.error,
  });

  factory DataImportResult.success(
    final ChatExport importedData,
    final FormDataPreset preset,
  ) => DataImportResult(
    success: true,
    importedData: importedData,
    formPreset: preset,
  );

  factory DataImportResult.failure(final String error) =>
      DataImportResult(success: false, error: error);
  final bool success;
  final ChatExport? importedData;
  final FormDataPreset? formPreset;
  final String? error;
}

class FormDataPreset {
  const FormDataPreset({
    required this.userName,
    required this.aiName,
    required this.meetStory,
    this.userBirthdate,
    this.userCountryCode,
    this.aiCountryCode,
  });
  final String userName;
  final String aiName;
  final String meetStory;
  final DateTime? userBirthdate;
  final String? userCountryCode;
  final String? aiCountryCode;
}

class DateParsingResult {
  const DateParsingResult({required this.success, this.parsedDate, this.error});

  factory DateParsingResult.success(final DateTime date) =>
      DateParsingResult(success: true, parsedDate: date);

  factory DateParsingResult.failure(final String error) =>
      DateParsingResult(success: false, error: error);
  final bool success;
  final DateTime? parsedDate;
  final String? error;
}

class FormCompletionAnalysis {
  const FormCompletionAnalysis({
    required this.isComplete,
    required this.missingFields,
    required this.completionPercentage,
    required this.hasChanges,
  });
  final bool isComplete;
  final List<String> missingFields;
  final double completionPercentage;
  final bool hasChanges;
}

/// DDD Application Service for Form-based Onboarding coordination and business logic
class FormOnboardingApplicationService {
  /// Validate form data with comprehensive business rules
  FormValidationResult validateFormData({
    required final String userName,
    required final String aiName,
    required final String meetStory,
    required final DateTime? userBirthdate,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) {
    final fieldErrors = <String, String>{};

    // Business rule: User name validation
    if (userName.trim().isEmpty) {
      fieldErrors['userName'] = 'User name is required';
    } else if (userName.trim().length < 2) {
      fieldErrors['userName'] = 'User name must be at least 2 characters';
    } else if (userName.trim().length > 50) {
      fieldErrors['userName'] = 'User name must be less than 50 characters';
    }

    // Business rule: AI name validation
    if (aiName.trim().isEmpty) {
      fieldErrors['aiName'] = 'AI name is required';
    } else if (aiName.trim().length < 2) {
      fieldErrors['aiName'] = 'AI name must be at least 2 characters';
    } else if (aiName.trim().length > 50) {
      fieldErrors['aiName'] = 'AI name must be less than 50 characters';
    }

    // Business rule: Meet story validation
    if (meetStory.trim().isEmpty || meetStory.trim() == 'AUTO_GENERATE_STORY') {
      // Allow auto-generate as valid
    } else if (meetStory.trim().length < 10) {
      fieldErrors['meetStory'] = 'Meet story must be at least 10 characters';
    }

    // Business rule: Birthdate validation
    if (userBirthdate == null) {
      fieldErrors['userBirthdate'] = 'Birthdate is required';
    } else {
      final now = DateTime.now();
      final age = now.year - userBirthdate.year;

      if (userBirthdate.isAfter(now)) {
        fieldErrors['userBirthdate'] = 'Birthdate cannot be in the future';
      } else if (age < 13) {
        fieldErrors['userBirthdate'] = 'Must be at least 13 years old';
      } else if (age > 120) {
        fieldErrors['userBirthdate'] = 'Please enter a valid birthdate';
      }
    }

    // Business rule: Duplicate names check
    if (userName.trim().toLowerCase() == aiName.trim().toLowerCase()) {
      fieldErrors['general'] = 'User name and AI name must be different';
    }

    final isValid = fieldErrors.isEmpty;
    return isValid
        ? FormValidationResult.success()
        : FormValidationResult.failure(fieldErrors: fieldErrors);
  }

  /// Coordinate JSON data import with business logic
  Future<DataImportResult> coordinateDataImport(final String jsonData) async {
    try {
      // Business rule: JSON must not be empty
      if (jsonData.trim().isEmpty) {
        return DataImportResult.failure('JSON data cannot be empty');
      }

      // Business rule: Import through proper service
      final chatExport = await ChatJsonUtils.importAllFromJson(
        jsonData,
        onError: (final error) => throw Exception(error),
      );

      if (chatExport == null) {
        return DataImportResult.failure('Failed to parse JSON data');
      }

      // Business rule: Extract form data from imported profile
      final profile = chatExport.profile;
      final preset = FormDataPreset(
        userName: profile.userName,
        aiName: profile.aiName,
        meetStory: 'AUTO_GENERATE_STORY', // Default since not in profile
        userBirthdate: profile.userBirthdate,
        userCountryCode: profile.userCountryCode,
        aiCountryCode: profile.aiCountryCode,
      );

      return DataImportResult.success(chatExport, preset);
    } on Exception catch (e) {
      return DataImportResult.failure('Import failed: $e');
    }
  }

  /// Parse date string with business rules
  DateParsingResult parseDateString(final String dateString) {
    try {
      if (dateString.trim().isEmpty) {
        return DateParsingResult.failure('Date string cannot be empty');
      }

      // Business rule: Support multiple date formats
      final cleanDate = dateString.trim();
      DateTime? parsedDate;

      // Try format: dd/mm/yyyy
      final parts = cleanDate.split('/');
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);

        if (day != null && month != null && year != null) {
          if (day > 0 && day <= 31 && month > 0 && month <= 12 && year > 1900) {
            parsedDate = DateTime(year, month, day);
          }
        }
      }

      // Try ISO format as fallback
      parsedDate ??= DateTime.tryParse(cleanDate);

      if (parsedDate == null) {
        return DateParsingResult.failure('Invalid date format. Use dd/mm/yyyy');
      }

      return DateParsingResult.success(parsedDate);
    } on Exception catch (e) {
      return DateParsingResult.failure('Date parsing failed: $e');
    }
  }

  /// Analyze form completion status
  FormCompletionAnalysis analyzeFormCompletion({
    required final String userName,
    required final String aiName,
    required final String meetStory,
    required final DateTime? userBirthdate,
    final String? userCountryCode,
    final String? aiCountryCode,
    required final bool hasImportedData,
  }) {
    final missingFields = <String>[];
    var filledFields = 0;
    const totalFields = 6;

    // Check each required field
    if (userName.trim().isEmpty) {
      missingFields.add('User Name');
    } else {
      filledFields++;
    }

    if (aiName.trim().isEmpty) {
      missingFields.add('AI Name');
    } else {
      filledFields++;
    }

    if (meetStory.trim().isEmpty || meetStory.trim() == 'AUTO_GENERATE_STORY') {
      // Auto-generate counts as filled
      filledFields++;
    } else {
      filledFields++;
    }

    if (userBirthdate == null) {
      missingFields.add('Birthdate');
    } else {
      filledFields++;
    }

    if (userCountryCode == null || userCountryCode.isEmpty) {
      missingFields.add('User Country');
    } else {
      filledFields++;
    }

    if (aiCountryCode == null || aiCountryCode.isEmpty) {
      missingFields.add('AI Country');
    } else {
      filledFields++;
    }

    final completionPercentage = (filledFields / totalFields) * 100;
    final isComplete = missingFields.isEmpty;

    // Determine if there are meaningful changes
    final hasChanges =
        userName.isNotEmpty ||
        aiName.isNotEmpty ||
        (meetStory != 'AUTO_GENERATE_STORY' && meetStory.isNotEmpty) ||
        userBirthdate != null ||
        userCountryCode != null ||
        aiCountryCode != null ||
        hasImportedData;

    return FormCompletionAnalysis(
      isComplete: isComplete,
      missingFields: missingFields,
      completionPercentage: completionPercentage,
      hasChanges: hasChanges,
    );
  }

  /// Process and create final onboarding result
  Future<OnboardingFormResult> processOnboardingData({
    required final String userName,
    required final String aiName,
    required final String meetStory,
    required final DateTime userBirthdate,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) async {
    try {
      // Business rule: Final validation before processing
      final validation = validateFormData(
        userName: userName,
        aiName: aiName,
        meetStory: meetStory,
        userBirthdate: userBirthdate,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );

      if (!validation.isValid) {
        final errorMessages = validation.fieldErrors.values.join(', ');
        return OnboardingFormResult.failure(errorMessages);
      }

      // Business rule: Create result with validated data
      return OnboardingFormResult.success(
        userName: userName.trim(),
        aiName: aiName.trim(),
        meetStory: meetStory.trim(),
        userBirthdate: userBirthdate,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
      );
    } on Exception catch (e) {
      return OnboardingFormResult.failure('Processing failed: $e');
    }
  }

  /// Format date for display
  String formatDateForDisplay(final DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Check if country code is valid (simple validation)
  bool isValidCountryCode(final String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return false;
    return countryCode.length == 2 && countryCode.toUpperCase() == countryCode;
  }

  /// Calculate user age
  int calculateAge(final DateTime birthdate) {
    final now = DateTime.now();
    int age = now.year - birthdate.year;
    if (now.month < birthdate.month ||
        (now.month == birthdate.month && now.day < birthdate.day)) {
      age--;
    }
    return age;
  }

  /// Generate form summary for display
  String generateFormSummary({
    required final String userName,
    required final String aiName,
    required final String meetStory,
    required final DateTime? userBirthdate,
    final String? userCountryCode,
    final String? aiCountryCode,
  }) {
    final summary = StringBuffer();

    summary.writeln('👤 User: $userName');
    summary.writeln('🤖 AI: $aiName');

    if (userBirthdate != null) {
      final age = calculateAge(userBirthdate);
      summary.writeln('🎂 Age: $age years old');
    }

    if (userCountryCode != null) {
      summary.writeln('🌍 User from: $userCountryCode');
    }

    if (aiCountryCode != null) {
      summary.writeln('🌐 AI from: $aiCountryCode');
    }

    if (meetStory.isNotEmpty && meetStory != 'AUTO_GENERATE_STORY') {
      summary.writeln('❤️ How we met: $meetStory');
    }

    return summary.toString().trim();
  }

  /// Validate individual field
  String? validateField(final String fieldName, final dynamic value) {
    switch (fieldName) {
      case 'userName':
        if (value == null || value.toString().trim().isEmpty) {
          return 'User name is required';
        }
        if (value.toString().trim().length < 2) {
          return 'User name must be at least 2 characters';
        }
        break;

      case 'aiName':
        if (value == null || value.toString().trim().isEmpty) {
          return 'AI name is required';
        }
        if (value.toString().trim().length < 2) {
          return 'AI name must be at least 2 characters';
        }
        break;

      case 'userBirthdate':
        if (value == null) {
          return 'Birthdate is required';
        }
        if (value is DateTime && value.isAfter(DateTime.now())) {
          return 'Birthdate cannot be in the future';
        }
        break;

      default:
        break;
    }
    return null;
  }
}
