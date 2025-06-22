package com.example.flutter_app

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.RecognitionListener
import android.os.Bundle
import android.media.MediaMetadataRetriever
import java.io.File
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "android_speech_recognition"
    private lateinit var speechRecognizer: SpeechRecognizer
    private lateinit var methodChannel: MethodChannel
    private var isListening = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    initialize(result)
                }
                "startListening" -> {
                    val locale = call.argument<String>("locale") ?: "ja-JP"
                    val partialResults = call.argument<Boolean>("partialResults") ?: true
                    val maxResults = call.argument<Int>("maxResults") ?: 5
                    startListening(locale, partialResults, maxResults, result)
                }
                "stopListening" -> {
                    stopListening(result)
                }
                "transcribeAudioFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val locale = call.argument<String>("locale") ?: "ja-JP"
                    if (filePath != null) {
                        transcribeAudioFile(filePath, locale, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                    }
                }
                "cleanup" -> {
                    cleanup(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        try {
            if (SpeechRecognizer.isRecognitionAvailable(this)) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        methodChannel.invokeMethod("onListeningStarted", null)
                    }

                    override fun onBeginningOfSpeech() {
                        // 音声検出開始
                    }

                    override fun onRmsChanged(rmsdB: Float) {
                        // 音声レベル変化（必要に応じて実装）
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {
                        // バッファ受信（通常は使用しない）
                    }

                    override fun onEndOfSpeech() {
                        // 音声検出終了
                    }

                    override fun onError(error: Int) {
                        isListening = false
                        val errorMsg = when (error) {
                            SpeechRecognizer.ERROR_AUDIO -> "error_audio"
                            SpeechRecognizer.ERROR_CLIENT -> "error_client"
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "error_permissions"
                            SpeechRecognizer.ERROR_NETWORK -> "error_network"
                            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "error_network_timeout"
                            SpeechRecognizer.ERROR_NO_MATCH -> "error_no_match"
                            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "error_recognizer_busy"
                            SpeechRecognizer.ERROR_SERVER -> "error_server"
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "error_speech_timeout"
                            else -> "error_unknown"
                        }
                        methodChannel.invokeMethod("onError", errorMsg)
                        methodChannel.invokeMethod("onListeningStopped", null)
                    }

                    override fun onResults(results: Bundle?) {
                        isListening = false
                        results?.let {
                            val matches = it.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                methodChannel.invokeMethod("onFinalResult", matches[0])
                            }
                        }
                        methodChannel.invokeMethod("onListeningStopped", null)
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        partialResults?.let {
                            val matches = it.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                methodChannel.invokeMethod("onPartialResult", matches[0])
                            }
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {
                        // イベント処理（必要に応じて実装）
                    }
                })
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.error("INITIALIZATION_ERROR", e.message, null)
        }
    }

    private fun startListening(locale: String, partialResults: Boolean, maxResults: Int, result: MethodChannel.Result) {
        try {
            if (isListening) {
                result.error("ALREADY_LISTENING", "Speech recognition is already active", null)
                return
            }

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, maxResults)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            
            speechRecognizer.startListening(intent)
            isListening = true
            result.success(true)
        } catch (e: Exception) {
            result.error("START_LISTENING_ERROR", e.message, null)
        }
    }

    private fun stopListening(result: MethodChannel.Result) {
        try {
            if (isListening) {
                speechRecognizer.stopListening()
                isListening = false
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_LISTENING_ERROR", e.message, null)
        }
    }

    private fun transcribeAudioFile(filePath: String, locale: String, result: MethodChannel.Result) {
        try {
            // 注意: Android Speech Recognition APIは直接音声ファイルからの認識をサポートしていません
            // ここでは簡易的な実装として、ファイルの存在確認とメタデータ読み取りのみを行います
            val file = File(filePath)
            if (!file.exists()) {
                result.success(mapOf("success" to false, "text" to null))
                return
            }

            // 音声ファイルのメタデータを確認
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(filePath)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = duration?.toLongOrNull() ?: 0L
                
                // 実際の音声認識は行わず、デモ用のダミーテキストを返す
                // 本格的な実装には Google Cloud Speech-to-Text API などのクラウドAPIが必要
                if (durationMs > 1000) { // 1秒以上の音声ファイル
                    val demoText = "音声ファイルから書き起こしました（デモ）"
                    result.success(mapOf("success" to true, "text" to demoText))
                } else {
                    result.success(mapOf("success" to false, "text" to null))
                }
            } catch (e: Exception) {
                result.success(mapOf("success" to false, "text" to null))
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            result.error("TRANSCRIBE_ERROR", e.message, null)
        }
    }

    private fun cleanup(result: MethodChannel.Result) {
        try {
            if (::speechRecognizer.isInitialized) {
                if (isListening) {
                    speechRecognizer.stopListening()
                }
                speechRecognizer.destroy()
                isListening = false
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("CLEANUP_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::speechRecognizer.isInitialized) {
            speechRecognizer.destroy()
        }
    }
}
