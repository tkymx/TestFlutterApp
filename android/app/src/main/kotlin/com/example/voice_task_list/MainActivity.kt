package com.example.voice_task_list

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import org.vosk.android.StorageService
import java.io.*
import java.util.concurrent.atomic.AtomicBoolean
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaCodec
import java.nio.ByteBuffer
import kotlin.math.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "android_speech_recognition"
    private val TAG = "VoskSpeechRecognition"
    
    private lateinit var methodChannel: MethodChannel
    private var speechService: SpeechService? = null
    private var model: Model? = null
    private var isListening = AtomicBoolean(false)
    private var isInitialized = AtomicBoolean(false)
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    companion object {
        private const val PERMISSIONS_REQUEST_RECORD_AUDIO = 1
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Voskのログレベル設定
        LibVosk.setLogLevel(LogLevel.INFO)
        
        // 権限チェック
        val permissionCheck = ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.RECORD_AUDIO)
        if (permissionCheck != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSIONS_REQUEST_RECORD_AUDIO)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    initialize(result)
                }
                "startListening" -> {
                    val locale = call.argument<String>("locale") ?: "ja"
                    val partialResults = call.argument<Boolean>("partialResults") ?: true
                    val maxResults = call.argument<Int>("maxResults") ?: 5
                    startListening(locale, partialResults, maxResults, result)
                }
                "stopListening" -> {
                    stopListening(result)
                }
                "transcribeAudioFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val locale = call.argument<String>("locale") ?: "ja"
                    if (filePath != null) {
                        transcribeAudioFile(filePath, locale, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                    }
                }
                "cleanup" -> {
                    cleanup(result)
                }
                "setModel" -> {
                    val modelId = call.argument<String>("modelId")
                    if (modelId != null) {
                        setModel(modelId, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "modelId is required", null)
                    }
                }
                "getAvailableModels" -> {
                    getAvailableModels(result)
                }
                "getInstalledModels" -> {
                    getInstalledModels(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (isInitialized.get()) {
            result.success(true)
            return
        }
        
        // 音声録音権限チェック
        val permissionCheck = ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.RECORD_AUDIO)
        if (permissionCheck != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSIONS_REQUEST_RECORD_AUDIO)
            result.error("PERMISSION_DENIED", "音声録音権限が必要です", null)
            return
        }
        
        scope.launch(Dispatchers.IO) {
            try {
                Log.d(TAG, "Vosk音声認識の初期化を開始...")
                
                // 内部ストレージのモデルディレクトリを確認
                val modelDir = File(filesDir, "vosk-model-small-ja-0.22")
                if (!modelDir.exists()) {
                    modelDir.mkdirs()
                    
                    // assetsからモデルファイルをコピー
                    try {
                        Log.d(TAG, "assetsからモデルファイルをコピー中...")
                        copyAssetsToInternal("vosk-model-small-ja-0.22", modelDir)
                        Log.d(TAG, "モデルファイルのコピーが完了しました")
                    } catch (e: Exception) {
                        Log.e(TAG, "モデルファイルコピーエラー", e)
                        runOnUiThread {
                            result.error("COPY_ERROR", "モデルファイルのコピーに失敗しました: ${e.message}", null)
                        }
                        return@launch
                    }
                }
                
                try {
                    Log.d(TAG, "モデルパス: ${modelDir.absolutePath}")
                    model = Model(modelDir.absolutePath)
                    isInitialized.set(true)
                    runOnUiThread {
                        Log.d(TAG, "Vosk音声認識の初期化に成功しました")
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "モデル読み込みエラー", e)
                    runOnUiThread {
                        result.error("MODEL_ERROR", "音声認識モデルの読み込みに失敗しました: ${e.message}", null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "初期化エラー", e)
                runOnUiThread {
                    result.error("INITIALIZATION_ERROR", "初期化に失敗しました: ${e.message}", null)
                }
            }
        }
    }

    private fun copyAssetsToInternal(assetPath: String, targetDir: File) {
        try {
            val assetManager = assets
            val files = assetManager.list(assetPath)
            
            if (files == null || files.isEmpty()) {
                // ファイルの場合
                val inputStream = assetManager.open(assetPath)
                val fileName = File(assetPath).name
                val targetFile = File(targetDir, fileName)
                
                // 親ディレクトリを作成
                targetFile.parentFile?.mkdirs()
                
                val outputStream = FileOutputStream(targetFile)
                inputStream.copyTo(outputStream)
                inputStream.close()
                outputStream.close()
                Log.d(TAG, "ファイルコピー完了: $fileName")
            } else {
                // ディレクトリの場合
                for (file in files) {
                    val subAssetPath = "$assetPath/$file"
                    val subTargetFile = File(targetDir, file)
                    
                    // サブディレクトリの場合
                    val subFiles = assetManager.list(subAssetPath)
                    if (subFiles != null && subFiles.isNotEmpty()) {
                        subTargetFile.mkdirs()
                        copyAssetsToInternal(subAssetPath, subTargetFile)
                    } else {
                        // ファイルの場合
                        val inputStream = assetManager.open(subAssetPath)
                        val outputStream = FileOutputStream(subTargetFile)
                        inputStream.copyTo(outputStream)
                        inputStream.close()
                        outputStream.close()
                        Log.d(TAG, "ファイルコピー完了: $subAssetPath")
                    }
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Assetsコピーエラー: $assetPath", e)
            throw e
        }
    }

    private fun startListening(locale: String, partialResults: Boolean, maxResults: Int, result: MethodChannel.Result) {
        if (!isInitialized.get()) {
            result.error("NOT_INITIALIZED", "音声認識が初期化されていません", null)
            return
        }
        
        if (isListening.get()) {
            result.error("ALREADY_LISTENING", "音声認識は既にアクティブです", null)
            return
        }

        try {
            Log.d(TAG, "音声認識開始...")
            
            speechService = SpeechService(Recognizer(model, 16000.0f), 16000.0f)
            speechService?.startListening(object : RecognitionListener {
                override fun onPartialResult(hypothesis: String?) {
                    Log.d(TAG, "部分結果: $hypothesis")
                    hypothesis?.let {
                        try {
                            val json = JSONObject(it)
                            val text = json.optString("partial", "")
                            if (text.isNotEmpty()) {
                                runOnUiThread {
                                    methodChannel.invokeMethod("onPartialResult", text)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "部分結果解析エラー", e)
                        }
                        Unit // 明示的にUnitを返す
                    }
                }

                override fun onResult(hypothesis: String?) {
                    Log.d(TAG, "最終結果: $hypothesis")
                    hypothesis?.let {
                        try {
                            val json = JSONObject(it)
                            val text = json.optString("text", "")
                            if (text.isNotEmpty()) {
                                runOnUiThread {
                                    methodChannel.invokeMethod("onFinalResult", text)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "最終結果解析エラー", e)
                        }
                        Unit // 明示的にUnitを返す
                    }
                }

                override fun onFinalResult(hypothesis: String?) {
                    Log.d(TAG, "認識完了: $hypothesis")
                    hypothesis?.let {
                        try {
                            val json = JSONObject(it)
                            val text = json.optString("text", "")
                            if (text.isNotEmpty()) {
                                runOnUiThread {
                                    methodChannel.invokeMethod("onFinalResult", text)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "最終結果解析エラー", e)
                        }
                        Unit // 明示的にUnitを返す
                    }
                    
                    isListening.set(false)
                    runOnUiThread {
                        methodChannel.invokeMethod("onListeningStopped", null)
                    }
                }

                override fun onError(exception: Exception?) {
                    Log.e(TAG, "音声認識エラー", exception)
                    isListening.set(false)
                    runOnUiThread {
                        val errorMsg = exception?.message ?: "音声認識エラーが発生しました"
                        methodChannel.invokeMethod("onError", errorMsg)
                        methodChannel.invokeMethod("onListeningStopped", null)
                    }
                }

                override fun onTimeout() {
                    Log.d(TAG, "音声認識タイムアウト")
                    isListening.set(false)
                    runOnUiThread {
                        methodChannel.invokeMethod("onError", "音声認識がタイムアウトしました")
                        methodChannel.invokeMethod("onListeningStopped", null)
                    }
                }
            })
            
            isListening.set(true)
            runOnUiThread {
                methodChannel.invokeMethod("onListeningStarted", null)
            }
            result.success(true)
            
        } catch (e: Exception) {
            Log.e(TAG, "音声認識開始エラー", e)
            result.error("START_LISTENING_ERROR", e.message, null)
        }
    }

    private fun stopListening(result: MethodChannel.Result) {
        try {
            if (isListening.get()) {
                Log.d(TAG, "音声認識停止...")
                speechService?.stop()
                speechService = null
                isListening.set(false)
                
                runOnUiThread {
                    methodChannel.invokeMethod("onListeningStopped", null)
                }
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "音声認識停止エラー", e)
            result.error("STOP_LISTENING_ERROR", e.message, null)
        }
    }

    private fun transcribeAudioFile(filePath: String, locale: String, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                Log.d(TAG, "音声ファイル文字起こし開始: $filePath")
                
                if (!isInitialized.get()) {
                    Log.e(TAG, "Vosk音声認識が初期化されていません")
                    runOnUiThread {
                        result.error("NOT_INITIALIZED", "音声認識が初期化されていません", null)
                    }
                    return@launch
                }
                
                val file = File(filePath)
                if (!file.exists()) {
                    Log.e(TAG, "音声ファイルが存在しません: $filePath")
                    runOnUiThread {
                        result.success(mapOf("success" to false, "text" to null))
                    }
                    return@launch
                }

                // ファイルサイズチェック
                val fileSize = file.length()
                Log.d(TAG, "音声ファイルサイズ: ${fileSize} bytes")
                if (fileSize < 1024) { // 1KB未満
                    Log.w(TAG, "音声ファイルが小さすぎます: ${fileSize} bytes")
                    runOnUiThread {
                        result.success(mapOf("success" to false, "text" to null))
                    }
                    return@launch
                }
                
                // モデルの状態確認
                if (model == null) {
                    Log.e(TAG, "Voskモデルがnullです")
                    runOnUiThread {
                        result.error("MODEL_ERROR", "音声認識モデルが利用できません", null)
                    }
                    return@launch
                }
                
                // 実際のVoskを使った音声ファイル書き起こし
                Log.d(TAG, "Vosk書き起こし処理開始...")
                val transcriptionResult = performVoskTranscription(filePath)
                
                runOnUiThread {
                    if (transcriptionResult != null) {
                        Log.d(TAG, "音声ファイル文字起こし完了: $transcriptionResult")
                        result.success(mapOf("success" to true, "text" to transcriptionResult))
                        methodChannel.invokeMethod("onFileTranscriptionResult", mapOf("success" to true, "text" to transcriptionResult))
                    } else {
                        Log.w(TAG, "音声ファイル文字起こし失敗 - 結果がnull")
                        result.success(mapOf("success" to false, "text" to null))
                        methodChannel.invokeMethod("onFileTranscriptionResult", mapOf("success" to false, "text" to null))
                    }
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "音声ファイル処理エラー", e)
                runOnUiThread {
                    result.error("TRANSCRIPTION_ERROR", "音声ファイル処理エラー: ${e.message}", null)
                }
            }
        }
    }

    private fun performVoskTranscription(filePath: String): String? {
        return try {
            Log.d(TAG, "Vosk音声ファイル認識開始: $filePath")
            
            // ファイルの詳細情報をログ出力
            val file = File(filePath)
            Log.d(TAG, "ファイル存在: ${file.exists()}, サイズ: ${file.length()} bytes")
            
            // 音声ファイルをPCMデータに変換
            val pcmData = convertAudioToPcm(filePath)
            if (pcmData == null) {
                Log.e(TAG, "音声ファイルのPCM変換に失敗")
                return null
            }
            
            Log.d(TAG, "PCM変換完了: ${pcmData.size} samples")
            
            // Voskで認識
            val recognizer = Recognizer(model, 16000.0f)
            val results = mutableListOf<String>()
            
            // 音声レベルの分析とノーマライゼーション
            val maxAmplitude = pcmData.maxOfOrNull { abs(it.toInt()) } ?: 1
            val avgAmplitude = pcmData.map { abs(it.toInt()) }.average()
            Log.d(TAG, "音声レベル分析 - 最大振幅: $maxAmplitude, 平均振幅: ${avgAmplitude.toInt()}")
            
            // 音声レベルが低すぎる場合は増幅
            val normalizedPcmData = if (maxAmplitude < 8000) {
                val amplifyFactor = (16000.0 / maxAmplitude).coerceAtMost(4.0) // 最大4倍まで増幅
                Log.d(TAG, "音声レベルが低いため増幅します（倍率: ${String.format("%.2f", amplifyFactor)}）")
                pcmData.map { sample ->
                    val amplified = (sample.toInt() * amplifyFactor).toInt()
                    amplified.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }.toShortArray()
            } else {
                Log.d(TAG, "音声レベルは適切です")
                pcmData
            }
            
            // PCMデータを16bit shortに変換してチャンクに分けて処理
            val pcmBytes = ByteArray(normalizedPcmData.size * 2) // 16bit = 2 bytes per sample
            for (i in normalizedPcmData.indices) {
                val sample = normalizedPcmData[i].toInt()
                pcmBytes[i * 2] = (sample and 0xFF).toByte()
                pcmBytes[i * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
            }
            
            Log.d(TAG, "PCMバイト配列作成完了: ${pcmBytes.size} bytes")
            
            // チャンクサイズを調整（3200バイト = 0.1秒分）
            val chunkSize = 3200
            var offset = 0
            var chunkCount = 0
            var hasVoiceActivity = false
            
            while (offset < pcmBytes.size) {
                val endOffset = minOf(offset + chunkSize, pcmBytes.size)
                val chunk = pcmBytes.sliceArray(offset until endOffset)
                chunkCount++
                
                // チャンクサイズチェック（偶数バイト数である必要がある）
                val adjustedChunk = if (chunk.size % 2 != 0 && chunk.size > 2) {
                    chunk.sliceArray(0 until chunk.size - 1)
                } else {
                    chunk
                }
                
                // 音声アクティビティ検出（振幅チェック）
                var chunkMaxAmplitude = 0
                for (i in adjustedChunk.indices step 2) {
                    if (i + 1 < adjustedChunk.size) {
                        val sample = ((adjustedChunk[i + 1].toInt() and 0xFF) shl 8) or (adjustedChunk[i].toInt() and 0xFF)
                        chunkMaxAmplitude = maxOf(chunkMaxAmplitude, abs(sample))
                    }
                }
                
                val isActiveVoice = chunkMaxAmplitude > 100 // 音声アクティビティの閾値
                if (isActiveVoice) hasVoiceActivity = true
                
                Log.d(TAG, "チャンク処理中: $chunkCount, サイズ: ${adjustedChunk.size}, オフセット: $offset, 最大振幅: $chunkMaxAmplitude, 音声あり: $isActiveVoice")
                
                try {
                    if (recognizer.acceptWaveForm(adjustedChunk, adjustedChunk.size)) {
                        val result = recognizer.result
                        Log.d(TAG, "中間結果 (チャンク$chunkCount): $result")
                        
                        try {
                            val json = JSONObject(result)
                            val text = json.optString("text", "")
                            if (text.isNotEmpty()) {
                                Log.d(TAG, "テキスト抽出成功: '$text'")
                                results.add(text)
                            }
                        } catch (jsonException: Exception) {
                            Log.w(TAG, "JSON解析エラー: ${jsonException.message}")
                        }
                    } else {
                        if (chunkCount % 20 == 0) { // 20チャンクごとにログ出力
                            Log.d(TAG, "チャンク${chunkCount}: 認識結果なし (進行中...)")
                        }
                    }
                } catch (voskException: Exception) {
                    Log.e(TAG, "Voskチャンク処理エラー: ${voskException.message}", voskException)
                }
                
                offset = endOffset
            }
            
            Log.d(TAG, "全チャンク処理完了。音声アクティビティ検出: $hasVoiceActivity")
            Log.d(TAG, "最終結果取得中...")
            
            // 最終結果を取得
            try {
                val finalResult = recognizer.finalResult
                Log.d(TAG, "最終結果JSON: $finalResult")
                
                val json = JSONObject(finalResult)
                val text = json.optString("text", "")
                if (text.isNotEmpty()) {
                    Log.d(TAG, "最終テキスト抽出成功: '$text'")
                    results.add(text)
                }
            } catch (finalException: Exception) {
                Log.e(TAG, "最終結果取得エラー: ${finalException.message}", finalException)
            }
            
            try {
                recognizer.close()
                Log.d(TAG, "Recognizerクローズ完了")
            } catch (closeException: Exception) {
                Log.w(TAG, "Recognizerクローズエラー: ${closeException.message}")
            }
            
            // 結果をまとめる
            val combinedResult = results.joinToString(" ").trim()
            Log.d(TAG, "抽出された結果数: ${results.size}")
            
            if (combinedResult.isNotEmpty()) {
                Log.d(TAG, "Vosk認識成功: '$combinedResult'")
                combinedResult
            } else {
                if (!hasVoiceActivity) {
                    Log.w(TAG, "音声アクティビティが検出されませんでした。録音レベルが低すぎる可能性があります。")
                } else {
                    Log.w(TAG, "音声は検出されましたが、認識可能な言語として解析できませんでした。")
                }
                Log.w(TAG, "Vosk認識結果なし - 音声が検出されませんでした")
                null
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Vosk認識エラー", e)
            null
        }
    }

    private fun convertAudioToPcm(filePath: String): ShortArray? {
        return try {
            Log.d(TAG, "音声ファイルPCM変換開始: $filePath")
            
            val file = File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "音声ファイルが存在しません: $filePath")
                return null
            }
            
            val fileSize = file.length()
            Log.d(TAG, "音声ファイルサイズ: ${fileSize} bytes")
            
            // MediaExtractorとMediaFormatを使用してM4A/AACファイルを処理
            val extractor = android.media.MediaExtractor()
            
            try {
                extractor.setDataSource(filePath)
                Log.d(TAG, "MediaExtractor初期化完了")
            } catch (e: Exception) {
                Log.e(TAG, "MediaExtractorのデータソース設定エラー", e)
                extractor.release()
                return null
            }
            
            var audioTrackIndex = -1
            var format: android.media.MediaFormat? = null
            
            Log.d(TAG, "トラック数: ${extractor.trackCount}")
            
            // 音声トラックを探す
            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val mime = trackFormat.getString(android.media.MediaFormat.KEY_MIME)
                Log.d(TAG, "トラック$i MIME: $mime")
                
                if (mime?.startsWith("audio/") == true) {
                    audioTrackIndex = i
                    format = trackFormat
                    Log.d(TAG, "音声トラック発見: インデックス=$i, MIME=$mime")
                    break
                }
            }
            
            if (audioTrackIndex == -1 || format == null) {
                Log.e(TAG, "音声トラックが見つかりません")
                extractor.release()
                return null
            }
            
            // 音声情報を詳細ログ出力
            val sampleRate = format.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT)
            val mime = format.getString(android.media.MediaFormat.KEY_MIME)
            Log.d(TAG, "音声フォーマット詳細 - サンプリングレート: ${sampleRate}Hz, チャンネル: $channels, MIME: $mime")
            
            extractor.selectTrack(audioTrackIndex)
            
            // MediaCodecでデコード
            val decoder = try {
                android.media.MediaCodec.createDecoderByType(mime!!)
            } catch (e: Exception) {
                Log.e(TAG, "MediaCodec作成エラー", e)
                extractor.release()
                return null
            }
            
            try {
                decoder.configure(format, null, null, 0)
                decoder.start()
                Log.d(TAG, "MediaCodec初期化完了")
            } catch (e: Exception) {
                Log.e(TAG, "MediaCodec設定エラー", e)
                decoder.release()
                extractor.release()
                return null
            }
            
            val bufferInfo = android.media.MediaCodec.BufferInfo()
            val pcmData = mutableListOf<Short>()
            var isEOS = false
            var inputBufferCount = 0
            var outputBufferCount = 0
            
            while (!isEOS) {
                // 入力バッファに音声データを送信
                val inputBufferIndex = decoder.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                    if (inputBuffer != null) {
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        inputBufferCount++
                        
                        if (sampleSize < 0) {
                            Log.d(TAG, "入力データ終了。入力バッファ数: $inputBufferCount")
                            decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        } else {
                            val presentationTimeUs = extractor.sampleTime
                            decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0)
                            extractor.advance()
                        }
                    }
                } else {
                    Log.d(TAG, "入力バッファ取得失敗: インデックス=$inputBufferIndex")
                }
                
                // 出力バッファからPCMデータを取得
                val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)
                when {
                    outputBufferIndex >= 0 -> {
                        outputBufferCount++
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        if (bufferInfo.size > 0 && outputBuffer != null) {
                            // PCMデータを16bit shortに変換
                            val pcmBytes = ByteArray(bufferInfo.size)
                            outputBuffer.get(pcmBytes)
                            outputBuffer.clear()
                            
                            // バイトデータをshortに変換（リトルエンディアン）
                            val tempPcmData = mutableListOf<Short>()
                            for (i in pcmBytes.indices step 2) {
                                if (i + 1 < pcmBytes.size) {
                                    val sample = ((pcmBytes[i + 1].toInt() and 0xFF) shl 8) or (pcmBytes[i].toInt() and 0xFF)
                                    tempPcmData.add(sample.toShort())
                                }
                            }
                            
                            // ステレオをモノラルに変換（必要な場合）
                            if (channels == 2) {
                                // ステレオの場合、左右チャンネルを平均化
                                for (i in tempPcmData.indices step 2) {
                                    if (i + 1 < tempPcmData.size) {
                                        val left = tempPcmData[i].toInt()
                                        val right = tempPcmData[i + 1].toInt()
                                        val mono = ((left + right) / 2).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                                        pcmData.add(mono.toShort())
                                    }
                                }
                            } else {
                                // モノラルの場合はそのまま追加
                                pcmData.addAll(tempPcmData)
                            }
                            
                            if (outputBufferCount % 10 == 0) {
                                Log.d(TAG, "PCMデータ処理中: 出力バッファ$outputBufferCount, PCMサンプル数: ${pcmData.size}")
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if (bufferInfo.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            Log.d(TAG, "出力データ終了。出力バッファ数: $outputBufferCount")
                            isEOS = true
                        }
                    }
                    outputBufferIndex == android.media.MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> {
                        Log.d(TAG, "出力バッファが変更されました")
                    }
                    outputBufferIndex == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = decoder.outputFormat
                        Log.d(TAG, "新しい出力フォーマット: $newFormat")
                    }
                    else -> {
                        Log.d(TAG, "出力バッファ取得失敗: インデックス=$outputBufferIndex")
                    }
                }
            }
            
            decoder.stop()
            decoder.release()
            extractor.release()
            
            Log.d(TAG, "デコード完了。PCMサンプル数: ${pcmData.size}")
            
            if (pcmData.isEmpty()) {
                Log.e(TAG, "PCMデータが空です")
                return null
            }
            
            // サンプリングレートを16kHzに変換（Voskの要求）
            val originalSampleRate = sampleRate
            val targetSampleRate = 16000
            
            var processedData = if (originalSampleRate != targetSampleRate) {
                Log.d(TAG, "サンプリングレート変換: ${originalSampleRate}Hz -> ${targetSampleRate}Hz")
                val resampled = resampleAudio(pcmData.toShortArray(), originalSampleRate, targetSampleRate)
                Log.d(TAG, "リサンプリング完了: ${resampled.size} samples")
                resampled
            } else {
                Log.d(TAG, "サンプリングレート変換不要")
                pcmData.toShortArray()
            }
            
            // 前後の無音部分をトリミング
            processedData = trimSilence(processedData)
            
            Log.d(TAG, "PCM変換完了: ${processedData.size} samples (${targetSampleRate}Hz)")
            processedData
            
        } catch (e: Exception) {
            Log.e(TAG, "PCM変換エラー", e)
            null
        }
    }

    private fun resampleAudio(input: ShortArray, inputSampleRate: Int, outputSampleRate: Int): ShortArray {
        if (inputSampleRate == outputSampleRate) {
            Log.d(TAG, "リサンプリング不要: 同じサンプリングレート")
            return input
        }
        
        Log.d(TAG, "リサンプリング開始: ${inputSampleRate}Hz -> ${outputSampleRate}Hz, 入力サンプル数: ${input.size}")
        
        val ratio = inputSampleRate.toDouble() / outputSampleRate.toDouble()
        val outputLength = (input.size / ratio).toInt()
        val output = ShortArray(outputLength)
        
        // より精密な線形補間を使用
        for (i in output.indices) {
            val sourceIndex = (i * ratio)
            val floorIndex = sourceIndex.toInt()
            val ceilIndex = (floorIndex + 1).coerceAtMost(input.size - 1)
            
            if (floorIndex >= input.size) {
                output[i] = 0
            } else if (floorIndex == ceilIndex) {
                output[i] = input[floorIndex]
            } else {
                // 線形補間
                val fraction = sourceIndex - floorIndex
                val sample1 = input[floorIndex].toDouble()
                val sample2 = input[ceilIndex].toDouble()
                val interpolated = sample1 + (sample2 - sample1) * fraction
                output[i] = interpolated.toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }
        
        Log.d(TAG, "リサンプリング完了: 出力サンプル数: ${output.size}")
        return output
    }

    private fun trimSilence(input: ShortArray, threshold: Int = 500): ShortArray {
        if (input.isEmpty()) return input
        
        Log.d(TAG, "無音トリミング開始: 入力サンプル数=${input.size}, 閾値=$threshold")
        
        // 先頭から音声開始位置を探す
        var startIndex = 0
        for (i in input.indices) {
            if (abs(input[i].toInt()) > threshold) {
                startIndex = maxOf(0, i - 1600) // 0.1秒分前から開始
                break
            }
        }
        
        // 末尾から音声終了位置を探す
        var endIndex = input.size - 1
        for (i in input.size - 1 downTo 0) {
            if (abs(input[i].toInt()) > threshold) {
                endIndex = minOf(input.size - 1, i + 1600) // 0.1秒分後まで含める
                break
            }
        }
        
        if (startIndex >= endIndex) {
            Log.w(TAG, "音声部分が見つかりませんでした。元データを返します。")
            return input
        }
        
        val trimmed = input.sliceArray(startIndex..endIndex)
        Log.d(TAG, "無音トリミング完了: 出力サンプル数=${trimmed.size} (${startIndex}→${endIndex})")
        
        return trimmed
    }

    private fun cleanup(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "クリーンアップ開始...")
            
            // 音声認識停止
            if (isListening.get()) {
                speechService?.stop()
                speechService = null
                isListening.set(false)
            }
            
            // モデルとリソースのクリーンアップ
            try {
                model?.close()
            } catch (e: Exception) {
                Log.w(TAG, "モデルクローズ時に例外発生: ${e.message}")
            }
            model = null
            isInitialized.set(false)
            
            Log.d(TAG, "クリーンアップ完了")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "クリーンアップエラー", e)
            result.error("CLEANUP_ERROR", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSIONS_REQUEST_RECORD_AUDIO) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "音声録音権限が付与されました")
            } else {
                Log.e(TAG, "音声録音権限が拒否されました")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        
        try {
            // コルーチンスコープのキャンセル
            scope.cancel()
            
            // 音声認識サービス停止
            speechService?.stop()
            speechService = null
            
            // モデルのクリーンアップ
            try {
                model?.close()
            } catch (e: Exception) {
                Log.w(TAG, "モデルクローズ時に例外発生: ${e.message}")
            }
            model = null
            
            isListening.set(false)
            isInitialized.set(false)
            
            Log.d(TAG, "アプリケーション終了時のクリーンアップ完了")
        } catch (e: Exception) {
            Log.e(TAG, "アプリケーション終了時のクリーンアップエラー", e)
        }
    }

    private fun setModel(modelId: String, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                Log.d(TAG, "モデル変更: $modelId")
                
                // 現在の音声認識を停止
                if (isListening.get()) {
                    speechService?.stop()
                    speechService = null
                    isListening.set(false)
                }
                
                // 現在のモデルをクローズ
                try {
                    model?.close()
                } catch (e: Exception) {
                    Log.w(TAG, "モデルクローズ時に例外発生: ${e.message}")
                }
                model = null
                isInitialized.set(false)
                
                // 新しいモデルを読み込み
                val modelFileName = getModelFileName(modelId)
                val modelDir = File(filesDir, modelFileName)
                
                if (!modelDir.exists()) {
                    runOnUiThread {
                        result.error("MODEL_NOT_FOUND", "指定されたモデルがインストールされていません: $modelId", null)
                    }
                    return@launch
                }
                
                try {
                    model = Model(modelDir.absolutePath)
                    isInitialized.set(true)
                    
                    runOnUiThread {
                        Log.d(TAG, "モデル変更完了: $modelId")
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "新しいモデル読み込みエラー", e)
                    runOnUiThread {
                        result.error("MODEL_LOAD_ERROR", "新しいモデルの読み込みに失敗しました: ${e.message}", null)
                    }
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "モデル変更エラー", e)
                runOnUiThread {
                    result.error("SET_MODEL_ERROR", "モデル変更に失敗しました: ${e.message}", null)
                }
            }
        }
    }

    private fun getAvailableModels(result: MethodChannel.Result) {
        val models = mapOf(
            "small" to mapOf(
                "id" to "small",
                "name" to "最小版モデル",
                "description" to "軽量で高速。基本的な音声認識に適している。",
                "size" to "40MB",
                "fileName" to "vosk-model-small-ja-0.22",
                "accuracy" to "標準"
            ),
            "large" to mapOf(
                "id" to "large",
                "name" to "高精度版モデル",
                "description" to "高精度の音声認識。専門用語や複雑な文章に対応。",
                "size" to "120MB",
                "fileName" to "vosk-model-ja-0.22",
                "accuracy" to "高精度"
            )
        )
        result.success(models)
    }

    private fun getInstalledModels(result: MethodChannel.Result) {
        try {
            val installedModels = mutableMapOf<String, Boolean>()
            val modelIds = listOf("small", "large")
            
            for (modelId in modelIds) {
                val modelFileName = getModelFileName(modelId)
                val modelDir = File(filesDir, modelFileName)
                installedModels[modelId] = modelDir.exists()
            }
            
            result.success(installedModels)
        } catch (e: Exception) {
            Log.e(TAG, "インストール済みモデル取得エラー", e)
            result.error("GET_INSTALLED_MODELS_ERROR", e.message, null)
        }
    }

    private fun getModelFileName(modelId: String): String {
        return when (modelId) {
            "small" -> "vosk-model-small-ja-0.22"
            "large" -> "vosk-model-ja-0.22"
            else -> "vosk-model-small-ja-0.22"
        }
    }
}
