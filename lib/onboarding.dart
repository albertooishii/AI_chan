// Onboarding Bounded Context Barrel Export

// Domain Layer
export 'onboarding/domain/models/onboarding_form_result.dart';

// Domain Interfaces
export 'onboarding/domain/interfaces/i_chat_export_service.dart';
export 'onboarding/domain/interfaces/i_file_picker_service.dart';
export 'onboarding/domain/interfaces/i_profile_repository.dart';
export 'onboarding/domain/interfaces/i_profile_service.dart';

// Domain Entities
export 'onboarding/domain/entities/memory_data.dart';

// Domain Services
export 'onboarding/domain/services/conversational_memory_domain_service.dart';

// Application Layer
export 'onboarding/application/services/form_onboarding_application_service.dart';
export 'onboarding/application/services/onboarding_application_service.dart';

// Application Use Cases
export 'onboarding/application/use_cases/biography_generation_use_case.dart';
export 'onboarding/application/use_cases/generate_next_question_use_case.dart';
export 'onboarding/application/use_cases/import_export_onboarding_use_case.dart';
export 'onboarding/application/use_cases/process_user_response_use_case.dart';
export 'onboarding/application/use_cases/save_chat_export_use_case.dart';

// Infrastructure Layer
export 'onboarding/infrastructure/adapters/chat_export_service_adapter.dart';
export 'onboarding/infrastructure/adapters/file_picker_service_adapter.dart';
export 'onboarding/infrastructure/adapters/in_memory_profile_repository.dart';
export 'onboarding/infrastructure/adapters/profile_adapter.dart';

// Presentation Layer

// Controllers - NOW HERE! ✅
export 'onboarding/presentation/controllers/form_onboarding_controller.dart';
export 'onboarding/presentation/controllers/onboarding_lifecycle_controller.dart';
export 'onboarding/presentation/controllers/onboarding_screen_controller.dart';

// Models
export 'onboarding/presentation/models/onboarding_step.dart'
    hide
        OnboardingStep; // Hide conflicting OnboardingStep from conversational_onboarding_screen

// Screens
export 'onboarding/presentation/screens/conversational_onboarding_screen.dart'
    show
        OnboardingStep; // Show OnboardingStep from conversational_onboarding_screen
export 'onboarding/presentation/screens/initializing_screen.dart';
export 'onboarding/presentation/screens/onboarding_mode_selector.dart'
    hide OnboardingFinishCallback; // Hide conflicting OnboardingFinishCallback
export 'onboarding/presentation/screens/onboarding_screen.dart'
    show
        OnboardingFinishCallback; // Show OnboardingFinishCallback from onboarding_screen

// Widgets
export 'onboarding/presentation/widgets/birth_date_field.dart';
