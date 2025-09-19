// 🎯 DDD: Puerto para servicios de grabación de audio en el contexto de voz
// Re-exporta la interfaz desde el dominio compartido

export 'package:ai_chan/shared/domain/interfaces/audio_recorder_service.dart'
    show
        IAudioRecorderService,
        AudioRecordingResult,
        AudioRecordingConfig,
        AudioRecorderException,
        AudioPermissionException;
