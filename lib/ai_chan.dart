// AI Chan - Main Project Barrel Export
//
// This is the main entry point for importing components from the AI Chan application.
// It exports all bounded contexts following DDD architecture patterns.

// Core Components
export 'main.dart';
export 'chat.dart';
export 'onboarding.dart';
export 'call.dart';
export 'core.dart';
export 'shared.dart';

// Bounded Contexts - Domain & Infrastructure Layers
export 'chat/domain.dart';
export 'chat/infrastructure.dart';
export 'onboarding/domain.dart';
export 'onboarding/infrastructure.dart';
export 'call/domain.dart';
export 'call/infrastructure.dart';
export 'core/domain.dart';
export 'core/infrastructure.dart';
export 'shared/domain.dart';
export 'shared/infrastructure.dart';
