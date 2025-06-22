import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:math';

/// ボイスメモデータクラス
class VoiceMemo {
  String id;
  String filePath;
  String title;
  DateTime createdAt;
  Duration duration;
  String? transcription;

  VoiceMemo({
    required this.id,
    required this.filePath,
    required this.title,
    required this.createdAt,
    this.duration = Duration.zero,
    this.transcription,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'duration': duration.inMilliseconds,
      'transcription': transcription,
    };
  }

  factory VoiceMemo.fromJson(Map<String, dynamic> json) {
    return VoiceMemo(
      id: json['id'],
      filePath: json['filePath'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      duration: Duration(milliseconds: json['duration'] ?? 0),
      transcription: json['transcription'],
    );
  }
}

/// 統合音声サービス
/// 録音、音声認識、連続音声認識、一時停止/再開機能を統合
/// Vosk Speech Recognition APIを使用
class UnifiedVoiceService {
  static final UnifiedVoiceService _instance = UnifiedVoiceService._internal();
  factory UnifiedVoiceService() => _instance;
  UnifiedVoiceService._internal() {
    _setupMethodChannel();
  }

  // Audio Recorder
  final AudioRecorder _recorder = AudioRecorder();
  
  // Vosk Speech Recognition API用のMethodChannel
  static const MethodChannel _channel = MethodChannel('android_speech_recognition');
  
  // 状態管理
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _speechEnabled = false;
  bool _isContinuousListening = false;
  bool _isPaused = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  String _recognizedText = '';
  String _accumulatedText = ''; // 連続音声認識で蓄積されるテキスト
  double _soundLevel = 0.0;
  
  // タイマー管理
  Timer? _restartTimer;
  Timer? _soundLevelTimer;
  int _restartAttempts = 0;
  static const int maxRestartAttempts = 5;
  static const Duration _restartInterval = Duration(seconds: 50);
  static const Duration _soundLevelUpdateInterval = Duration(milliseconds: 100);
  
  // ボイスメモ専用の録音状態
  String? _voiceMemoRecordingPath;
  DateTime? _voiceMemoRecordingStartTime;
  bool _isVoiceMemoRecording = false;
  
  // コールバック
  Function(VoiceMemo)? onVoiceMemoCreated;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;
  Function(String)? onTranscriptionUpdated;
  Function(String)? onStatusChanged;
  
  // ゲッター
  bool get isRecording => _isRecording || _isVoiceMemoRecording;
  bool get isVoiceMemoRecording => _isVoiceMemoRecording;
  bool get isInitialized => _isInitialized;
  bool get speechEnabled => _speechEnabled;
  bool get isContinuousListening => _isContinuousListening;
  bool get isPaused => _isPaused;
  String get recognizedText => _recognizedText;
  String get accumulatedText => _accumulatedText;
  double get soundLevel => _soundLevel;

  /// MethodChannelのセットアップ
  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPartialResult':
          final text = call.arguments as String;
          _recognizedText = text;
          // 連続音声認識中は部分的な結果を蓄積テキストに一時的に追加
          if (_isContinuousListening) {
            final displayText = _accumulatedText + (_accumulatedText.isNotEmpty ? ' ' : '') + text;
            onTranscriptionUpdated?.call(displayText);
          } else {
            onTranscriptionUpdated?.call(text);
          }
          break;
        case 'onFinalResult':
          final text = call.arguments as String;
          _recognizedText = text;
          // 連続音声認識中は最終結果を蓄積テキストに追加
          if (_isContinuousListening && text.trim().isNotEmpty) {
            _accumulatedText += (_accumulatedText.isNotEmpty ? ' ' : '') + text.trim();
            onTranscriptionUpdated?.call(_accumulatedText);
          } else {
            onTranscriptionUpdated?.call(text);
          }
          break;
        case 'onError':
          final error = call.arguments as String;
          print('音声認識エラー: $error');
          _handleSpeechError(error);
          break;
        case 'onListeningStarted':
          print('音声認識開始');
          break;
        case 'onListeningStopped':
          print('音声認識停止');
          break;
        case 'onFileTranscriptionResult':
          final result = call.arguments as Map<dynamic, dynamic>;
          final text = result['text'] as String?;
          final success = result['success'] as bool;
          if (success && text != null) {
            print('ファイル書き起こし成功: $text');
          } else {
            print('ファイル書き起こし失敗');
          }
          break;
      }
    });
  }

  /// サービスの初期化
  Future<bool> initialize() async {
    try {
      print('統合音声サービスの初期化を開始します...');
      
      // Webプラットフォームでは制限された機能のみ
      if (kIsWeb) {
        print('Webプラットフォームでは機能制限があります');
        onError?.call('Webプラットフォームではボイスメモ機能は制限されています');
        return false;
      }

      // 権限チェック
      bool permissionsGranted = await _checkPermissions();
      if (!permissionsGranted) {
        print('権限が付与されていません。一部機能が制限される可能性があります');
      }

      // 録音機能の初期化確認
      bool recorderInitialized = await _initializeRecorder();
      if (!recorderInitialized) {
        print('録音機能の初期化に失敗しました。録音機能が制限される可能性があります');
      }
      
      // Vosk Speech Recognition APIの初期化
      try {
        final result = await _channel.invokeMethod('initialize');
        _speechEnabled = result == true;
        if (_speechEnabled) {
          print('Vosk Speech Recognition APIの初期化に成功しました');
        } else {
          print('Vosk Speech Recognition APIの初期化に失敗しました');
        }
      } catch (e) {
        print('Vosk Speech Recognition API初期化エラー: $e');
        _speechEnabled = false;
        
        // 各種エラーに対するフォールバック処理
        final errorMessage = e.toString().toLowerCase();
        if (errorMessage.contains('native') || 
            errorMessage.contains('jna') || 
            errorMessage.contains('libvosk') ||
            errorMessage.contains('unsatisfiedlinkerror') ||
            errorMessage.contains('permission') ||
            errorMessage.contains('model') ||
            errorMessage.contains('download')) {
          print('音声認識機能は無効ですが、録音機能で続行します');
          onError?.call('音声認識機能が利用できません。録音機能のみ使用できます。');
        } else {
          onError?.call('音声認識初期化エラー: $e');
        }
      }
      
      _isInitialized = true;
      print('統合音声サービスの初期化が完了しました');
      return true;
    } catch (e) {
      print('初期化エラー: $e');
      onError?.call('初期化エラー: $e');
      return false;
    }
  }

  /// 録音機能の初期化確認
  Future<bool> _initializeRecorder() async {
    try {
      final isRecorderInitialized = await _recorder.isEncoderSupported(
        AudioEncoder.aacLc,
      );
      print('録音機能初期化状態: $isRecorderInitialized');
      return isRecorderInitialized;
    } catch (e) {
      print('録音機能初期化エラー: $e');
      return true; // エラーが発生しても続行を試みる
    }
  }

  /// 権限チェック
  Future<bool> _checkPermissions() async {
    if (kIsWeb) return false;

    try {
      final permissions = [Permission.microphone];
      
      // Android 13未満の場合はストレージ権限も追加
      if (!kIsWeb && Platform.isAndroid) {
        final deviceInfo = await Permission.storage.status;
        if (deviceInfo != PermissionStatus.granted) {
          permissions.add(Permission.storage);
        }
      }

      Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      bool allGranted = statuses.values.every((status) => 
        status == PermissionStatus.granted || status == PermissionStatus.limited);
      
      print('権限チェック結果: $allGranted (${statuses.toString()})');
      return allGranted;
    } catch (e) {
      print('権限チェックエラー: $e');
      return true; // エラーが発生した場合でも処理を続行
    }
  }

  /// 通常の録音開始（リアルタイム音声認識付き）
  Future<void> startRecording() async {
    if (_isRecording || kIsWeb) return;

    try {
      // ファイルパス生成
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'voice_memo_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = '${directory.path}/$fileName';

      // 録音設定を高品質に設定
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recognizedText = '';
      onRecordingStateChanged?.call(true);
      
      // リアルタイム音声認識開始（少し遅延させて録音が安定してから開始）
      await Future.delayed(const Duration(milliseconds: 500));
      await _startSpeechRecognition();
      
      _startSoundLevelSimulation();
      onStatusChanged?.call('録音開始 - 話しかけてください');
      print('録音を開始しました: $_currentRecordingPath');
    } catch (e) {
      _isRecording = false;
      onRecordingStateChanged?.call(false);
      onError?.call('録音開始エラー: $e');
    }
  }

  /// 録音停止
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      // リアルタイム音声認識停止
      await _stopSpeechRecognition();
      
      // 少し待ってから録音停止（最後の音声を確実に録音）
      await Future.delayed(const Duration(milliseconds: 300));
      
      final path = await _recorder.stop();
      _isRecording = false;
      _stopTimers();
      _soundLevel = 0.0;
      onRecordingStateChanged?.call(false);
      onStatusChanged?.call('録音停止 - 処理中...');

      if (path != null && _recordingStartTime != null) {
        await _processRecordedFile(path, _recordingStartTime!);
      } else {
        onError?.call('録音ファイルの保存に失敗しました');
      }
      
      _currentRecordingPath = null;
      _recordingStartTime = null;
    } catch (e) {
      print('録音停止エラー: $e');
      onError?.call('録音停止エラー: $e');
      _currentRecordingPath = null;
      _recordingStartTime = null;
      _isRecording = false;
      onRecordingStateChanged?.call(false);
    }
  }

  /// 連続音声認識の開始（録音なし）
  Future<void> startContinuousListening() async {
    if (!_isInitialized || !_speechEnabled) {
      onError?.call('音声認識が利用できません');
      return;
    }

    if (_isContinuousListening) {
      print('連続音声認識は既に開始されています');
      return;
    }

    try {
      _isContinuousListening = true;
      _isPaused = false;
      _restartAttempts = 0;
      _recognizedText = '';
      _accumulatedText = ''; // 連続音声認識開始時に蓄積テキストをクリア
      
      await _startListening();
      onStatusChanged?.call('連続音声認識開始');
      print('連続音声認識を開始しました');
    } catch (e) {
      _isContinuousListening = false;
      print('連続音声認識開始エラー: $e');
      onError?.call('連続音声認識開始エラー: $e');
    }
  }

  /// 連続音声認識の一時停止
  Future<void> pauseListening() async {
    if (!_isContinuousListening || _isPaused) {
      return;
    }

    try {
      _isPaused = true;
      await _channel.invokeMethod('stopListening');
      _stopTimers();
      onStatusChanged?.call('一時停止中');
      print('連続音声認識を一時停止しました');
    } catch (e) {
      print('連続音声認識一時停止エラー: $e');
      onError?.call('連続音声認識一時停止エラー: $e');
    }
  }

  /// 連続音声認識の再開
  Future<void> resumeListening() async {
    if (!_isContinuousListening || !_isPaused) {
      return;
    }

    try {
      _isPaused = false;
      await _startListening();
      onStatusChanged?.call('音声認識再開');
      print('連続音声認識を再開しました');
    } catch (e) {
      print('連続音声認識再開エラー: $e');
      onError?.call('連続音声認識再開エラー: $e');
    }
  }

  /// 連続音声認識の停止
  Future<void> stopListening() async {
    if (!_isContinuousListening) {
      return;
    }

    try {
      _isContinuousListening = false;
      _isPaused = false;
      await _channel.invokeMethod('stopListening');
      _stopTimers();
      onStatusChanged?.call('音声認識停止');
      print('連続音声認識を停止しました');
    } catch (e) {
      print('連続音声認識停止エラー: $e');
      onError?.call('連続音声認識停止エラー: $e');
    }
  }

  /// 音声認識の開始（内部用）
  Future<void> _startSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    _recognizedText = '';
    // 通常の録音時は蓄積テキストもクリア
    if (!_isContinuousListening) {
      _accumulatedText = '';
    }
    await _startListening();
  }

  /// 実際の音声認識開始
  Future<void> _startListening() async {
    if (!_speechEnabled) return;

    try {
      await _channel.invokeMethod('startListening', {
        'locale': 'ja',  // Vosk用のロケール形式
        'partialResults': true,
        'maxResults': 5,
      });
      
      if (_isContinuousListening) {
        _startRestartTimer();
      }
      
      print('Vosk音声認識を開始しました');
    } catch (e) {
      print('Vosk音声認識開始エラー: $e');
      if (_isContinuousListening) {
        _scheduleRestart();
      }
    }
  }

  /// 音声認識の停止（内部用）
  Future<void> _stopSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    try {
      await _channel.invokeMethod('stopListening');
      print('音声認識を停止しました');
    } catch (e) {
      print('音声認識停止エラー: $e');
    }
  }

  /// 自動再起動タイマーの開始
  void _startRestartTimer() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartInterval, () {
      if (_isContinuousListening && !_isPaused) {
        _restartListening();
      }
    });
  }

  /// 音声認識の自動再起動
  Future<void> _restartListening() async {
    try {
      if (!_isContinuousListening || _isPaused) return;
      
      print('音声認識を自動再起動します (試行回数: ${_restartAttempts + 1})');
      await _channel.invokeMethod('stopListening');
      await Future.delayed(const Duration(milliseconds: 500));
      await _startListening();
      _restartAttempts = 0;
    } catch (e) {
      print('音声認識自動再起動エラー: $e');
      _scheduleRestart();
    }
  }

  /// 再起動のスケジュール
  void _scheduleRestart() {
    if (!_isContinuousListening || _restartAttempts >= maxRestartAttempts) return;
    
    _restartTimer?.cancel();
    _restartAttempts++;
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      _restartListening();
    });
  }

  /// 音声レベルのシミュレーション開始
  void _startSoundLevelSimulation() {
    _soundLevelTimer?.cancel();
    _soundLevelTimer = Timer.periodic(_soundLevelUpdateInterval, (timer) {
      if (_isRecording || _isContinuousListening) {
        _soundLevel = _generateRandomSoundLevel();
      } else {
        timer.cancel();
        _soundLevel = 0.0;
      }
    });
  }

  /// ランダムな音声レベルを生成（デモ用）
  double _generateRandomSoundLevel() {
    final random = Random();
    return random.nextDouble() * 0.8 + 0.1; // 0.1 から 0.9 の範囲
  }

  /// タイマーの停止
  void _stopTimers() {
    _restartTimer?.cancel();
    _soundLevelTimer?.cancel();
  }

  /// 録音ファイルの処理（リアルタイム認識の結果と合わせて保存）
  Future<void> _processRecordedFile(String path, DateTime startTime) async {
    try {
      final file = File(path);
      final fileExists = await file.exists();
      if (!fileExists) {
        onError?.call('録音ファイルが見つかりません: $path');
        return;
      }

      final fileSize = await file.length();
      if (fileSize <= 1024) {
        onError?.call('録音時間が短すぎます。もう一度お試しください。');
        try { await file.delete(); } catch (e) {}
        return;
      }

      final duration = DateTime.now().difference(startTime);
      
      // リアルタイム認識の結果を使用
      String? transcriptionText = _recognizedText.isNotEmpty ? _recognizedText : null;
      
      String title;
      if (transcriptionText != null && transcriptionText.isNotEmpty) {
        final titleText = transcriptionText.length > 20 
            ? '${transcriptionText.substring(0, 20)}...' 
            : transcriptionText;
        title = titleText;
      } else {
        title = 'ボイスメモ ${DateTime.now().month}/${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      }

      final voiceMemo = VoiceMemo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: path,
        title: title,
        createdAt: startTime,
        duration: duration,
        transcription: transcriptionText,
      );

      // 保存
      final saveSuccess = await saveVoiceMemo(voiceMemo);
      if (saveSuccess) {
        onVoiceMemoCreated?.call(voiceMemo);
        if (transcriptionText != null && transcriptionText.isNotEmpty) {
          onTranscriptionUpdated?.call(transcriptionText);
          onStatusChanged?.call('録音完了 - 書き起こし成功');
        } else {
          onStatusChanged?.call('録音完了 - 書き起こしなし');
        }
        print('録音を停止しました: $path (サイズ: ${(fileSize / 1024).toStringAsFixed(1)}KB)');
        print('書き起こし: ${voiceMemo.transcription ?? "なし"}');
      } else {
        onError?.call('ボイスメモの保存に失敗しました');
      }
    } catch (e) {
      print('録音ファイル処理エラー: $e');
      onError?.call('録音ファイル処理エラー: $e');
    }
  }

  /// ボイスメモ専用の録音開始（録音のみ、音声認識なし）
  Future<void> startVoiceMemoRecording() async {
    if (_isVoiceMemoRecording || kIsWeb) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'voice_memo_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _voiceMemoRecordingPath = '${directory.path}/$fileName';
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _voiceMemoRecordingPath!,
      );
      
      _isVoiceMemoRecording = true;
      _voiceMemoRecordingStartTime = DateTime.now();
      onRecordingStateChanged?.call(true);
      onStatusChanged?.call('録音開始');
      print('ボイスメモ録音を開始: $_voiceMemoRecordingPath');
    } catch (e) {
      _isVoiceMemoRecording = false;
      onRecordingStateChanged?.call(false);
      onError?.call('ボイスメモ録音開始エラー: $e');
    }
  }

  /// ボイスメモ専用の録音停止（録音のみ、録音後に音声認識）
  Future<void> stopVoiceMemoRecording() async {
    if (!_isVoiceMemoRecording) return;
    
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final path = await _recorder.stop();
      _isVoiceMemoRecording = false;
      onRecordingStateChanged?.call(false);
      onStatusChanged?.call('録音停止 - 書き起こし中...');
      
      if (path != null && _voiceMemoRecordingStartTime != null) {
        await _processVoiceMemoRecordedFile(path, _voiceMemoRecordingStartTime!);
      } else {
        onError?.call('録音パスまたは開始時間が不正です');
      }
      
      _voiceMemoRecordingPath = null;
      _voiceMemoRecordingStartTime = null;
    } catch (e) {
      print('ボイスメモ録音停止エラー: $e');
      onError?.call('ボイスメモ録音停止エラー: $e');
      _voiceMemoRecordingPath = null;
      _voiceMemoRecordingStartTime = null;
      _isVoiceMemoRecording = false;
      onRecordingStateChanged?.call(false);
    }
  }

  /// ボイスメモ録音ファイルの処理（録音後に音声認識）
  Future<void> _processVoiceMemoRecordedFile(String path, DateTime startTime) async {
    try {
      final file = File(path);
      final fileExists = await file.exists();
      if (!fileExists) {
        onError?.call('録音ファイルが見つかりません: $path');
        return;
      }
      
      final fileSize = await file.length();
      if (fileSize <= 1024) {
        onError?.call('録音時間が短すぎます。もう一度お試しください。');
        try { await file.delete(); } catch (e) {}
        return;
      }
      
      final duration = DateTime.now().difference(startTime);
      
      // 録音後に音声ファイルから書き起こしを実行
      String? transcriptionText;
      try {
        transcriptionText = await transcribeAudioFile(path);
      } catch (e) {
        print('書き起こし失敗: $e');
        transcriptionText = null;
      }
      
      String title;
      if (transcriptionText != null && transcriptionText.isNotEmpty) {
        final titleText = transcriptionText.length > 20 
            ? '${transcriptionText.substring(0, 20)}...' 
            : transcriptionText;
        title = titleText;
      } else {
        title = 'ボイスメモ ${DateTime.now().month}/${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      }
      
      final voiceMemo = VoiceMemo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: path,
        title: title,
        createdAt: startTime,
        duration: duration,
        transcription: transcriptionText,
      );
      
      final saveSuccess = await saveVoiceMemo(voiceMemo);
      if (saveSuccess) {
        onVoiceMemoCreated?.call(voiceMemo);
        if (transcriptionText != null && transcriptionText.isNotEmpty) {
          onTranscriptionUpdated?.call(transcriptionText);
          onStatusChanged?.call('録音完了 - 書き起こし成功');
        } else {
          onStatusChanged?.call('録音完了 - 書き起こしなし');
        }
        print('録音を停止しました: $path (サイズ: ${(fileSize / 1024).toStringAsFixed(1)}KB)');
        print('書き起こし: ${voiceMemo.transcription ?? "なし"}');
      } else {
        onError?.call('ボイスメモの保存に失敗しました');
      }
    } catch (e) {
      print('ボイスメモ録音ファイル処理エラー: $e');
      onError?.call('ボイスメモ録音ファイル処理エラー: $e');
    }
  }

  /// 音声ファイルから書き起こしを行う（Android Speech Recognition API使用）
  Future<String?> transcribeAudioFile(String filePath) async {
    try {
      if (kIsWeb) {
        // WebではWeb Speech APIを使用（ただし音声ファイルからの認識は制限あり）
        onStatusChanged?.call('書き起こし中（Web Speech API）...');
        await Future.delayed(const Duration(seconds: 2));
        return 'Web環境では音声ファイルからの書き起こしに制限があります';
      }
      
      // モバイル環境では Android Speech Recognition API を使用
      onStatusChanged?.call('書き起こし中...');
      
      if (!_speechEnabled) {
        print('音声認識が無効です');
        return null;
      }
      
      // ファイルの存在確認
      final file = File(filePath);
      if (!await file.exists()) {
        print('音声ファイルが存在しません: $filePath');
        return null;
      }
      
      // Voskで音声ファイルから書き起こし
      try {
        final result = await _channel.invokeMethod('transcribeAudioFile', {
          'filePath': filePath,
          'locale': 'ja',  // Vosk用のロケール形式
        });
        
        if (result != null && result is Map) {
          final success = result['success'] as bool;
          final text = result['text'] as String?;
          
          if (success && text != null && text.isNotEmpty) {
            print('Vosk音声ファイル書き起こし成功: $text');
            return text;
          } else {
            print('Vosk音声ファイル書き起こし失敗または結果なし');
            return null;
          }
        } else {
          print('Vosk音声ファイル書き起こし結果が不正です');
          return null;
        }
      } catch (e) {
        print('Vosk音声ファイル書き起こしエラー: $e');
        
        // VoskのJNIエラーの場合、録音のみ対応であることを通知
        if (e.toString().contains('Native') || 
            e.toString().contains('JNA') || 
            e.toString().contains('libvosk') ||
            e.toString().contains('UnsatisfiedLinkError')) {
          print('音声認識ライブラリエラー: 録音機能のみ利用可能です');
          onStatusChanged?.call('音声認識機能が利用できません');
        }
        return null;
      }
      
    } catch (e) {
      print('transcribeAudioFile エラー: $e');
      return null;
    }
  }

  /// 音声認識エラーハンドリング
  void _handleSpeechError(String error) {
    print('音声認識エラー: $error');
    
    // error_no_matchは正常な状況（音声が認識されなかった）なので無視
    if (error == 'error_no_match') {
      print('音声が認識されませんでした（正常）');
      return;
    }
    
    // 連続音声認識中の場合、回復可能なエラーは再試行
    if (_isContinuousListening) {
      if (error.contains('network') || 
          error.contains('audio') || 
          error.contains('recognizer_busy')) {
        _scheduleRestart();
      } else {
        onError?.call('音声認識エラー: $error');
      }
    } else {
      onError?.call('音声認識エラー: $error');
    }
  }

  /// 手動音声メモの作成（連続音声認識用）
  Future<VoiceMemo?> createManualVoiceMemo() async {
    final textToUse = _isContinuousListening ? _accumulatedText : _recognizedText;
    if (textToUse.isEmpty) {
      onError?.call('認識されたテキストがありません');
      return null;
    }

    try {
      final title = textToUse.length > 20 
          ? '${textToUse.substring(0, 20)}...' 
          : textToUse;
          
      final voiceMemo = VoiceMemo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: '', // 音声ファイルなし
        title: title,
        createdAt: DateTime.now(),
        duration: Duration.zero,
        transcription: textToUse,
      );

      final saveSuccess = await saveVoiceMemo(voiceMemo);
      if (saveSuccess) {
        onVoiceMemoCreated?.call(voiceMemo);
        onStatusChanged?.call('音声メモを作成しました');
        print('手動音声メモを作成しました: $title');
        return voiceMemo;
      } else {
        onError?.call('音声メモの保存に失敗しました');
        return null;
      }
    } catch (e) {
      print('手動音声メモ作成エラー: $e');
      onError?.call('手動音声メモ作成エラー: $e');
      return null;
    }
  }

  /// ボイスメモ保存
  Future<bool> saveVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceMemosString = prefs.getString('voice_memos') ?? '[]';
      final voiceMemosJson = jsonDecode(voiceMemosString) as List;
      
      voiceMemosJson.insert(0, voiceMemo.toJson());
      await prefs.setString('voice_memos', jsonEncode(voiceMemosJson));
      
      return true;
    } catch (e) {
      print('ボイスメモ保存エラー: $e');
      return false;
    }
  }

  /// ボイスメモ一覧取得
  Future<List<VoiceMemo>> getVoiceMemos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceMemosString = prefs.getString('voice_memos') ?? '[]';
      final voiceMemosJson = jsonDecode(voiceMemosString) as List;
      
      return voiceMemosJson.map((json) => VoiceMemo.fromJson(json)).toList();
    } catch (e) {
      print('ボイスメモ一覧取得エラー: $e');
      return [];
    }
  }

  /// ボイスメモ削除
  Future<void> deleteVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      // ファイルがある場合は削除
      if (voiceMemo.filePath.isNotEmpty) {
        final file = File(voiceMemo.filePath);
        if (await file.exists()) {
          await file.delete();
          print('ボイスメモファイルを削除しました: ${voiceMemo.filePath}');
        }
      }

      // メタデータから削除
      final prefs = await SharedPreferences.getInstance();
      final voiceMemosString = prefs.getString('voice_memos') ?? '[]';
      final voiceMemosJson = jsonDecode(voiceMemosString) as List;
      
      voiceMemosJson.removeWhere((json) => json['id'] == voiceMemo.id);
      await prefs.setString('voice_memos', jsonEncode(voiceMemosJson));
      
      print('ボイスメモを削除しました: ${voiceMemo.title}');
    } catch (e) {
      print('ボイスメモ削除エラー: $e');
    }
  }

  /// リソース解放
  void dispose() {
    _isContinuousListening = false;
    _isPaused = false;
    _stopTimers();
    _recorder.dispose();
    
    // Vosk Speech Recognition APIのクリーンアップ
    try {
      _channel.invokeMethod('cleanup');
    } catch (e) {
      print('Vosk Speech Recognition API クリーンアップエラー: $e');
    }
    
    _isInitialized = false;
    _recognizedText = '';
    _accumulatedText = '';
    _soundLevel = 0.0;
    
    if (kDebugMode) {
      print('統合音声サービスのリソースを解放しました');
    }
  }
}
