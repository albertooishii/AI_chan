// Example: How to use the new barrel exports
//
// Instead of importing individual files like:
// import 'package:ai_chan/chat/domain/interfaces/i_chat_service.dart';
// import 'package:ai_chan/chat/domain/models/chat_message.dart';
// import 'package:ai_chan/onboarding/domain/interfaces/i_profile_service.dart';
//
// You can now import entire bounded contexts:
// import 'package:ai_chan/chat.dart'; // Imports domain, infrastructure, application, presentation
// import 'package:ai_chan/onboarding.dart'; // Imports all onboarding layers
// import 'package:ai_chan/call.dart'; // Imports all call layers
// import 'package:ai_chan/core.dart'; // Imports core components
// import 'package:ai_chan/shared.dart'; // Imports shared kernel
// import 'package:ai_chan/ai_chan.dart'; // Imports everything from the main project
//
// The barrel files by layer (domain.dart, infrastructure.dart, application.dart)
// have been consolidated into the main bounded context files for cleaner imports.

// This file demonstrates the consolidated barrel export system implementation
