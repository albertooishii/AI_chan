// Core Bounded Context Barrel Export

// Domain Layer
export 'core/domain/interfaces/i_call_to_chat_communication_service.dart';

// Infrastructure Layer
export 'core/infrastructure/adapters/gemini_adapter.dart';

// Interfaces
export 'core/interfaces.dart';

// Models
export 'core/models.dart';

// Core Services & Configuration
export 'core/config.dart';
export 'core/di.dart';
export 'core/di_bootstrap.dart';
export 'core/http_connector.dart';
export 'core/network_connectors.dart';
export 'core/ai_runtime_guard.dart';

// Specific Services
export 'core/services/ia_appearance_generator.dart';
export 'core/services/ia_avatar_generator.dart';
export 'core/services/ia_bio_generator.dart';
export 'core/services/image_request_service.dart';
export 'core/services/memory_summary_service.dart';
