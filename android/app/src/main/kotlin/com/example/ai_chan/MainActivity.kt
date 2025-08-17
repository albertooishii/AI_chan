package com.example.ai_chan

import io.flutter.embedding.android.FlutterActivity

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.*

class MainActivity : FlutterActivity() {
    private val BLUETOOTH_CHANNEL = "bluetooth_sco"
    private val TTS_CHANNEL = "ai_chan/native_tts"
    
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Canal existente para Bluetooth
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_CHANNEL).setMethodCallHandler { call, result ->
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "startSco" -> {
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                    result.success(true)
                }
                "stopSco" -> {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                    audioManager.mode = AudioManager.MODE_NORMAL
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Nuevo canal para TTS nativo
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    result.success(ttsReady)
                }
                "getVoices" -> {
                    if (ttsReady && textToSpeech != null) {
                        val voices = textToSpeech!!.voices
                        val voiceList = mutableListOf<Map<String, Any>>()
                        
                        for (voice in voices) {
                            val voiceMap = mapOf(
                                "name" to voice.name,
                                "locale" to voice.locale.toString(),
                                "quality" to when (voice.quality) {
                                    Voice.QUALITY_VERY_HIGH -> "very_high"
                                    Voice.QUALITY_HIGH -> "high"
                                    Voice.QUALITY_NORMAL -> "normal"
                                    else -> "low"
                                },
                                "latency" to when (voice.latency) {
                                    Voice.LATENCY_VERY_LOW -> "very_low"
                                    Voice.LATENCY_LOW -> "low"
                                    Voice.LATENCY_NORMAL -> "normal"
                                    else -> "high"
                                },
                                "requiresNetworkConnection" to voice.isNetworkConnectionRequired,
                                "isInstalled" to !voice.isNetworkConnectionRequired
                            )
                            voiceList.add(voiceMap)
                        }
                        
                        result.success(voiceList)
                    } else {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                "speak" -> {
                    if (ttsReady && textToSpeech != null) {
                        val text = call.argument<String>("text") ?: ""
                        val voiceName = call.argument<String>("voiceName")
                        val languageCode = call.argument<String>("languageCode") ?: "es-ES"
                        val pitch = call.argument<Double>("pitch")?.toFloat() ?: 1.0f
                        val speechRate = call.argument<Double>("speechRate")?.toFloat() ?: 1.0f
                        
                        // Configurar voz si se especifica
                        if (voiceName != null) {
                            val voices = textToSpeech!!.voices
                            val selectedVoice = voices.find { it.name == voiceName }
                            if (selectedVoice != null) {
                                textToSpeech!!.voice = selectedVoice
                            }
                        } else {
                            // Configurar idioma
                            val parts = languageCode.split("-")
                            val language = parts[0]
                            val country = if (parts.size > 1) parts[1] else ""
                            val locale = if (country.isNotEmpty()) Locale(language, country) else Locale(language)
                            textToSpeech!!.language = locale
                        }
                        
                        // Configurar parámetros de voz
                        textToSpeech!!.setPitch(pitch)
                        textToSpeech!!.setSpeechRate(speechRate)
                        
                        val speechResult = textToSpeech!!.speak(text, TextToSpeech.QUEUE_FLUSH, null, "tts_utterance")
                        result.success(speechResult == TextToSpeech.SUCCESS)
                    } else {
                        result.success(false)
                    }
                }
                "synthesizeToFile" -> {
                    if (ttsReady && textToSpeech != null) {
                        val text = call.argument<String>("text") ?: ""
                        val outputPath = call.argument<String>("outputPath") ?: ""
                        val voiceName = call.argument<String>("voiceName")
                        val languageCode = call.argument<String>("languageCode") ?: "es-ES"
                        val pitch = call.argument<Double>("pitch")?.toFloat() ?: 1.0f
                        val speechRate = call.argument<Double>("speechRate")?.toFloat() ?: 1.0f
                        
                        if (outputPath.isEmpty()) {
                            result.error("INVALID_PATH", "Output path is empty", null)
                            return@setMethodCallHandler
                        }
                        
                        // Configurar voz si se especifica
                        if (voiceName != null) {
                            val voices = textToSpeech!!.voices
                            val selectedVoice = voices.find { it.name == voiceName }
                            if (selectedVoice != null) {
                                textToSpeech!!.voice = selectedVoice
                            }
                        } else {
                            // Configurar idioma
                            val parts = languageCode.split("-")
                            val language = parts[0]
                            val country = if (parts.size > 1) parts[1] else ""
                            val locale = if (country.isNotEmpty()) Locale(language, country) else Locale(language)
                            textToSpeech!!.language = locale
                        }
                        
                        // Configurar parámetros de voz
                        textToSpeech!!.setPitch(pitch)
                        textToSpeech!!.setSpeechRate(speechRate)
                        
                        val file = File(outputPath)
                        val bundle = Bundle()
                        bundle.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "file_synthesis")
                        
                        val synthesisResult = textToSpeech!!.synthesizeToFile(text, bundle, file, "file_synthesis")
                        if (synthesisResult == TextToSpeech.SUCCESS) {
                            result.success(outputPath)
                        } else {
                            result.error("SYNTHESIS_FAILED", "Failed to synthesize to file", null)
                        }
                    } else {
                        result.error("TTS_NOT_READY", "TextToSpeech not ready", null)
                    }
                }
                "stop" -> {
                    if (ttsReady && textToSpeech != null) {
                        val stopResult = textToSpeech!!.stop()
                        result.success(stopResult == TextToSpeech.SUCCESS)
                    } else {
                        result.success(false)
                    }
                }
                "getDownloadableLanguages" -> {
                    // En Android, esto requeriría acceso a la configuración del sistema
                    // Por simplicidad, devolvemos una lista básica de idiomas comunes
                    val languages = listOf(
                        mapOf("code" to "es-ES", "name" to "Español (España)"),
                        mapOf("code" to "es-MX", "name" to "Español (México)"),
                        mapOf("code" to "es-AR", "name" to "Español (Argentina)"),
                        mapOf("code" to "en-US", "name" to "English (US)"),
                        mapOf("code" to "en-GB", "name" to "English (UK)"),
                        mapOf("code" to "fr-FR", "name" to "Français"),
                        mapOf("code" to "de-DE", "name" to "Deutsch"),
                        mapOf("code" to "it-IT", "name" to "Italiano"),
                        mapOf("code" to "pt-BR", "name" to "Português (Brasil)"),
                        mapOf("code" to "ja-JP", "name" to "日本語"),
                        mapOf("code" to "ko-KR", "name" to "한국어"),
                        mapOf("code" to "zh-CN", "name" to "中文 (简体)"),
                        mapOf("code" to "ru-RU", "name" to "Русский")
                    )
                    result.success(languages)
                }
                "requestDownload" -> {
                    // En Android, esto normalmente abriría la configuración de TTS
                    // Por simplicidad, devolvemos true
                    result.success(true)
                }
                "getDownloadStatus" -> {
                    val languageCode = call.argument<String>("languageCode") ?: ""
                    // Verificar si el idioma está disponible
                    if (ttsReady && textToSpeech != null) {
                        val parts = languageCode.split("-")
                        val language = parts[0]
                        val country = if (parts.size > 1) parts[1] else ""
                        val locale = if (country.isNotEmpty()) Locale(language, country) else Locale(language)
                        
                        val status = when (textToSpeech!!.isLanguageAvailable(locale)) {
                            TextToSpeech.LANG_AVAILABLE -> "available"
                            TextToSpeech.LANG_COUNTRY_AVAILABLE -> "available"
                            TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE -> "available"
                            TextToSpeech.LANG_MISSING_DATA -> "missing_data"
                            TextToSpeech.LANG_NOT_SUPPORTED -> "not_supported"
                            else -> "unknown"
                        }
                        result.success(status)
                    } else {
                        result.success("not_ready")
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Inicializar TextToSpeech
        initializeTextToSpeech()
    }
    
    private fun initializeTextToSpeech() {
        textToSpeech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                // Configurar listener para eventos de síntesis
                textToSpeech!!.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        // Se puede usar para notificar que comenzó la síntesis
                    }
                    
                    override fun onDone(utteranceId: String?) {
                        // Se puede usar para notificar que terminó la síntesis
                    }
                    
                    override fun onError(utteranceId: String?) {
                        // Se puede usar para notificar errores
                    }
                })
            } else {
                ttsReady = false
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        textToSpeech?.shutdown()
    }
}
