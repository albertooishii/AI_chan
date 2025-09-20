// 🎯 DDD: Exportación de interfaces de servicios de voz
// Facilita la importación desde el contexto de voz
//
// Note: Now using centralized services directly instead of duplicated interfaces

export 'package:ai_chan/shared/ai_providers/core/services/audio/centralized_tts_service.dart'
    show CentralizedTtsService;
export 'package:ai_chan/shared/ai_providers/core/services/audio/centralized_stt_service.dart'
    show CentralizedSttService;
