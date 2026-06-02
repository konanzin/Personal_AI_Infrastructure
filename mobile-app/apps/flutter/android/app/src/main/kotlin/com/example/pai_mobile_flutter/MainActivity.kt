package com.example.pai_mobile_flutter

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pai_mobile_flutter/voice"
    private var speechRecognizer: SpeechRecognizer? = null
    private var methodChannel: MethodChannel? = null
    private var isListening = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initSpeechRecognizer" -> {
                    initSpeechRecognizer()
                    result.success(true)
                }
                "startListening" -> {
                    val locale = call.argument<String>("locale") ?: "pt-BR"
                    startListening(locale)
                    result.success(true)
                }
                "stopListening" -> {
                    stopListening()
                    result.success(true)
                }
                "isListening" -> {
                    result.success(isListening)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initSpeechRecognizer() {
        if (speechRecognizer != null) return
        
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    methodChannel?.invokeMethod("onSpeechStatus", mapOf("status" to "listening"))
                }

                override fun onBeginningOfSpeech() {
                    methodChannel?.invokeMethod("onSpeechStatus", mapOf("status" to "started"))
                }

                override fun onRmsChanged(rmsdB: Float) {
                    methodChannel?.invokeMethod("onSoundLevel", mapOf("level" to rmsdB))
                }

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    methodChannel?.invokeMethod("onSpeechStatus", mapOf("status" to "stopped"))
                    isListening = false
                }

                override fun onError(error: Int) {
                    isListening = false
                    val errorMessage = when (error) {
                        SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                        SpeechRecognizer.ERROR_CLIENT -> "Client side error"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
                        SpeechRecognizer.ERROR_NETWORK -> "Network error"
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                        SpeechRecognizer.ERROR_NO_MATCH -> "No speech recognized"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                        SpeechRecognizer.ERROR_SERVER -> "Server error"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input"
                        else -> "Unknown error: $error"
                    }
                    methodChannel?.invokeMethod("onSpeechError", mapOf("error" to errorMessage))
                }

                override fun onResults(results: Bundle?) {
                    isListening = false
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (matches != null && matches.isNotEmpty()) {
                        val text = matches[0]
                        val confidence = results.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                        methodChannel?.invokeMethod("onSpeechResult", mapOf(
                            "text" to text,
                            "confidence" to (confidence?.get(0) ?: 0.0f)
                        ))
                    } else {
                        methodChannel?.invokeMethod("onSpeechError", mapOf("error" to "No speech recognized"))
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (matches != null && matches.isNotEmpty()) {
                        methodChannel?.invokeMethod("onSpeechPartial", mapOf("text" to matches[0]))
                    }
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        }
    }

    private fun startListening(locale: String) {
        if (speechRecognizer == null) {
            initSpeechRecognizer()
        }
        
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        
        isListening = true
        speechRecognizer?.startListening(intent)
    }

    private fun stopListening() {
        speechRecognizer?.stopListening()
        isListening = false
    }

    override fun onDestroy() {
        speechRecognizer?.destroy()
        super.onDestroy()
    }
}
