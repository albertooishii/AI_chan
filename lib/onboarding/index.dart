// Onboarding Domain Layer Barrel Export

// Models - use canonical version from core
export 'package:ai_chan/core/models/ai_chan_profile.dart';
export 'domain/models/onboarding_form_result.dart';

// Interfaces (Ports)
export 'domain/interfaces/i_profile_service.dart';
export 'domain/interfaces/i_profile_repository.dart';

// Services
export 'domain/services/conversational_memory_domain_service.dart';
export 'services/index.dart';
