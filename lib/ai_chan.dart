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
export 'chat/index.dart';
export 'chat/infrastructure/index.dart';
export 'onboarding/index.dart';
export 'onboarding/infrastructure/index.dart';
export 'call/index.dart';
export 'call/infrastructure/index.dart';
export 'core/index.dart';
export 'core/infrastructure/index.dart';
export 'shared/index.dart';
export 'shared/infrastructure/index.dart';
