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

    private fun copyModelFiles(targetDir: File) {
        try {
            // 一般的なVoskモデルファイル構造
            val modelFiles = listOf(
                "am/final.mdl",
                "graph/HCLG.fst", 
                "graph/phones.txt",
                "graph/words.txt",
                "ivector/final.dubm",
                "ivector/final.ie",
                "ivector/final.mat",
                "ivector/global_cmvn.stats",
                "ivector/online_cmvn.conf",
                "ivector/splice.conf",
                "conf/mfcc.conf",
                "conf/model.conf"
            )
            
            for (modelFile in modelFiles) {
                try {
                    val inputStream = assets.open("vosk-model/$modelFile")
                    val targetFile = File(targetDir, modelFile)
                    
                    // 親ディレクトリを作成
                    targetFile.parentFile?.mkdirs()
                    
                    val outputStream = FileOutputStream(targetFile)
                    inputStream.copyTo(outputStream)
                    inputStream.close()
                    outputStream.close()
                    
                    Log.d(TAG, "コピー完了: $modelFile")
                } catch (e: Exception) {
                    Log.w(TAG, "ファイルコピー失敗: $modelFile - ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "モデルファイルコピーエラー", e)
            throw e
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
                    runOnUiThread {
                        result.error("NOT_INITIALIZED", "音声認識が初期化されていません", null)
                    }
                    return@launch
                }
                
                val file = File(filePath)
                if (!file.exists()) {
                    runOnUiThread {
                        result.success(mapOf("success" to false, "text" to null))
                    }
                    return@launch
                }

                // ファイルサイズチェック
                val fileSize = file.length()
                if (fileSize < 1024) { // 1KB未満
                    runOnUiThread {
                        result.success(mapOf("success" to false, "text" to null))
                    }
                    return@launch
                }
                
                // 実際のVoskを使った音声ファイル書き起こし
                val transcriptionResult = performVoskTranscription(filePath)
                
                runOnUiThread {
                    if (transcriptionResult != null) {
                        Log.d(TAG, "音声ファイル文字起こし完了: $transcriptionResult")
                        result.success(mapOf("success" to true, "text" to transcriptionResult))
                        methodChannel.invokeMethod("onFileTranscriptionResult", mapOf("success" to true, "text" to transcriptionResult))
                    } else {
                        Log.d(TAG, "音声ファイル文字起こし失敗")
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
            
            // 音声ファイルをPCMデータに変換
            val pcmData = convertAudioToPcm(filePath)
            if (pcmData == null) {
                Log.e(TAG, "音声ファイルのPCM変換に失敗")
                return null
            }
            
            // Voskで認識
            val recognizer = Recognizer(model, 16000.0f)
            val results = mutableListOf<String>()
            
            // PCMデータをバイト配列に変換してチャンクに分けて処理
            val pcmBytes = ByteArray(pcmData.size * 2) // 16bit = 2 bytes per sample
            for (i in pcmData.indices) {
                val sample = pcmData[i].toInt()
                pcmBytes[i * 2] = (sample and 0xFF).toByte()
                pcmBytes[i * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
            }
            
            val chunkSize = 8000 // 16000Hz * 0.25秒 * 2 bytes
            var offset = 0
            
            while (offset < pcmBytes.size) {
                val endOffset = minOf(offset + chunkSize, pcmBytes.size)
                val chunk = pcmBytes.sliceArray(offset until endOffset)
                
                if (recognizer.acceptWaveForm(chunk, chunk.size)) {
                    val result = recognizer.result
                    Log.d(TAG, "中間結果: $result")
                    
                    try {
                        val json = JSONObject(result)
                        val text = json.optString("text", "")
                        if (text.isNotEmpty()) {
                            results.add(text)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "JSON解析エラー: $e")
                    }
                }
                
                offset = endOffset
            }
            
            // 最終結果を取得
            val finalResult = recognizer.finalResult
            Log.d(TAG, "最終結果: $finalResult")
            
            try {
                val json = JSONObject(finalResult)
                val text = json.optString("text", "")
                if (text.isNotEmpty()) {
                    results.add(text)
                }
            } catch (e: Exception) {
                Log.w(TAG, "最終結果JSON解析エラー: $e")
            }
            
            recognizer.close()
            
            // 結果をまとめる
            val combinedResult = results.joinToString(" ").trim()
            
            if (combinedResult.isNotEmpty()) {
                Log.d(TAG, "Vosk認識成功: $combinedResult")
                combinedResult
            } else {
                Log.d(TAG, "Vosk認識結果なし")
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
            
            // MediaExtractorとMediaFormatを使用してM4A/AACファイルを処理
            val extractor = android.media.MediaExtractor()
            extractor.setDataSource(filePath)
            
            var audioTrackIndex = -1
            var format: android.media.MediaFormat? = null
            
            // 音声トラックを探す
            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val mime = trackFormat.getString(android.media.MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) {
                    audioTrackIndex = i
                    format = trackFormat
                    break
                }
            }
            
            if (audioTrackIndex == -1 || format == null) {
                Log.e(TAG, "音声トラックが見つかりません")
                extractor.release()
                return null
            }
            
            extractor.selectTrack(audioTrackIndex)
            
            // MediaCodecでデコード
            val mime = format.getString(android.media.MediaFormat.KEY_MIME)!!
            val decoder = android.media.MediaCodec.createDecoderByType(mime)
            
            decoder.configure(format, null, null, 0)
            decoder.start()
            
            val bufferInfo = android.media.MediaCodec.BufferInfo()
            
            val pcmData = mutableListOf<Short>()
            var isEOS = false
            
            while (!isEOS) {
                // 入力バッファに音声データを送信
                val inputBufferIndex = decoder.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                    val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                    
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    } else {
                        val presentationTimeUs = extractor.sampleTime
                        decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0)
                        extractor.advance()
                    }
                }
                
                // 出力バッファからPCMデータを取得
                val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)
                when {
                    outputBufferIndex >= 0 -> {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        if (bufferInfo.size > 0 && outputBuffer != null) {
                            // PCMデータを16bit shortに変換
                            val pcmBytes = ByteArray(bufferInfo.size)
                            outputBuffer.get(pcmBytes)
                            outputBuffer.clear()
                            
                            // バイトデータをshortに変換（リトルエンディアン）
                            for (i in pcmBytes.indices step 2) {
                                if (i + 1 < pcmBytes.size) {
                                    val sample = ((pcmBytes[i + 1].toInt() and 0xFF) shl 8) or (pcmBytes[i].toInt() and 0xFF)
                                    pcmData.add(sample.toShort())
                                }
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if (bufferInfo.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            isEOS = true
                        }
                    }
                    outputBufferIndex == android.media.MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> {
                        // 出力バッファが変更された（新しいAPIでは不要）
                    }
                    outputBufferIndex == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        // 出力フォーマットが変更された
                        val newFormat = decoder.outputFormat
                        Log.d(TAG, "新しい出力フォーマット: $newFormat")
                    }
                }
            }
            
            decoder.stop()
            decoder.release()
            extractor.release()
            
            // サンプリングレートを16kHzに変換（Voskの要求）
            val originalSampleRate = format.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
            val targetSampleRate = 16000
            
            val result = if (originalSampleRate != targetSampleRate) {
                Log.d(TAG, "サンプリングレート変換: ${originalSampleRate}Hz -> ${targetSampleRate}Hz")
                resampleAudio(pcmData.toShortArray(), originalSampleRate, targetSampleRate)
            } else {
                pcmData.toShortArray()
            }
            
            Log.d(TAG, "PCM変換完了: ${result.size} samples (${targetSampleRate}Hz)")
            result
            
        } catch (e: Exception) {
            Log.e(TAG, "PCM変換エラー", e)
            null
        }
    }

    private fun resampleAudio(input: ShortArray, inputSampleRate: Int, outputSampleRate: Int): ShortArray {
        if (inputSampleRate == outputSampleRate) {
            return input
        }
        
        val ratio = inputSampleRate.toDouble() / outputSampleRate.toDouble()
        val outputLength = (input.size / ratio).toInt()
        val output = ShortArray(outputLength)
        
        for (i in output.indices) {
            val inputIndex = (i * ratio).toInt()
            if (inputIndex < input.size) {
                output[i] = input[inputIndex]
            }
        }
        
        return output
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
