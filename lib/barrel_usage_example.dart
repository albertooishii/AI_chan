// Example: How to use the new barrel exports
//
// Instead of importing individual files like:
// import 'package:ai_chan/chat/domain/interfaces/i_chat_service.dart';
// import 'package:ai_chan/chat/domain/models/chat_message.dart';
// import 'package:ai_chan/onboarding/domain/interfaces/i_profile_service.dart';
//
// You can now import entire layers:
// import 'package:ai_chan/chat.dart'; // Imports domain, infrastructure, application, presentation
// import 'package:ai_chan/onboarding.dart'; // Imports all onboarding layers
// import 'package:ai_chan/ai_chan.dart'; // Imports everything from the main project
//
// Or import specific layers:
// import 'package:ai_chan/chat/domain.dart'; // Only domain layer from chat
// import 'package:ai_chan/shared/infrastructure.dart'; // Only infrastructure from shared

// This file demonstrates the barrel export system implementation
