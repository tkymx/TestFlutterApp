import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
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
class UnifiedVoiceService {
  static final UnifiedVoiceService _instance = UnifiedVoiceService._internal();
  factory UnifiedVoiceService() => _instance;
  UnifiedVoiceService._internal();

  // Audio Recorder
  final AudioRecorder _recorder = AudioRecorder();
  
  // Speech to Text
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  
  // 状態管理
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _speechEnabled = false;
  bool _isContinuousListening = false;
  bool _isPaused = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  String _recognizedText = '';
  double _soundLevel = 0.0;
  
  // タイマー管理
  Timer? _restartTimer;
  Timer? _soundLevelTimer;
  int _restartAttempts = 0;
  static const int maxRestartAttempts = 5;
  static const Duration _restartInterval = Duration(seconds: 50);
  static const Duration _soundLevelUpdateInterval = Duration(milliseconds: 100);
  
  // コールバック
  Function(VoiceMemo)? onVoiceMemoCreated;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;
  Function(String)? onTranscriptionUpdated;
  Function(String)? onStatusChanged;
  
  // ゲッター
  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;
  bool get speechEnabled => _speechEnabled;
  bool get isContinuousListening => _isContinuousListening;
  bool get isPaused => _isPaused;
  String get recognizedText => _recognizedText;
  double get soundLevel => _soundLevel;

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
        print('録音機能の初期化に失敗しました');
        onError?.call('録音機能の初期化に失敗しました');
        return false;
      }
      
      // 音声認識機能の初期化
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          _handleSpeechError(error);
        },
        onStatus: (status) {
          _handleStatusChange(status);
        },
      );
      
      if (!_speechEnabled) {
        print('音声認識機能の初期化に失敗しました。書き起こし機能が制限されます');
      } else {
        print('音声認識機能の初期化に成功しました');
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
        try {
          final version = Platform.version.split('.')[0];
          if (int.parse(version) < 33) {
            permissions.add(Permission.storage);
          }
        } catch (e) {
          print('Androidバージョン解析エラー: $e');
        }
      }

      Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      bool allGranted = statuses.values.every((status) => 
        status == PermissionStatus.granted || 
        status == PermissionStatus.limited);
      
      print('権限チェック結果: $allGranted (${statuses.toString()})');
      return allGranted;
    } catch (e) {
      print('権限チェックエラー: $e');
      return true; // エラーが発生した場合でも処理を続行
    }
  }

  /// 通常の録音開始
  Future<void> startRecording() async {
    if (_isRecording || kIsWeb) return;

    try {
      // ファイルパス生成
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'voice_memo_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = '${directory.path}/$fileName';

      // 録音開始
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
      
      // 音声認識開始
      await _startSpeechRecognition();
      print('録音を開始しました: $_currentRecordingPath');
    } catch (e) {
      onError?.call('録音開始エラー: $e');
    }
  }

  /// 録音停止
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      onRecordingStateChanged?.call(false);
      
      // 音声認識停止
      await _stopSpeechRecognition();

      if (path != null && _recordingStartTime != null) {
        await _processRecordedFile(path);
      } else {
        onError?.call('録音ファイルの取得に失敗しました');
      }

      _currentRecordingPath = null;
      _recordingStartTime = null;
    } catch (e) {
      print('録音停止エラー詳細: $e');
      onError?.call('録音停止エラー: $e');
      _currentRecordingPath = null;
      _recordingStartTime = null;
    }
  }

  /// 連続音声認識の開始（録音なし）
  Future<void> startContinuousListening() async {
    if (!_isInitialized || !_speechEnabled) {
      onError?.call('音声認識サービスが初期化されていません');
      return;
    }

    if (_isContinuousListening) {
      onStatusChanged?.call('既に音声認識中です');
      return;
    }

    try {
      _isContinuousListening = true;
      _isPaused = false;
      _recognizedText = '';
      
      await _startListening();
      _startRestartTimer();
      _startSoundLevelSimulation();
      
      onStatusChanged?.call('連続音声認識開始');
    } catch (e) {
      onError?.call('連続音声認識開始エラー: $e');
      _isContinuousListening = false;
    }
  }

  /// 連続音声認識の一時停止
  Future<void> pauseListening() async {
    if (!_isContinuousListening || _isPaused) {
      return;
    }

    try {
      _isPaused = true;
      await _speechToText.stop();
      _stopTimers();
      onStatusChanged?.call('一時停止中');
    } catch (e) {
      onError?.call('一時停止エラー: $e');
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
      _startRestartTimer();
      _startSoundLevelSimulation();
      onStatusChanged?.call('音声認識再開');
    } catch (e) {
      onError?.call('再開エラー: $e');
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
      await _speechToText.stop();
      _stopTimers();
      _soundLevel = 0.0;
      onStatusChanged?.call('音声認識停止');
    } catch (e) {
      onError?.call('停止エラー: $e');
    }
  }

  /// 音声認識の開始（内部用）
  Future<void> _startSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    _recognizedText = '';
    await _startListening();
  }

  /// 実際の音声認識開始
  Future<void> _startListening() async {
    if (!_speechEnabled) return;

    try {
      await _speechToText.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            _recognizedText = result.recognizedWords;
            onTranscriptionUpdated?.call(_recognizedText);
          }
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'ja_JP',
        cancelOnError: false,
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (e) {
      print('音声認識開始エラー: $e');
      if (_isContinuousListening) {
        _scheduleRestart();
      }
    }
  }

  /// 音声認識の停止（内部用）
  Future<void> _stopSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    try {
      await _speechToText.stop();
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
      if (kDebugMode) {
        print('音声認識を自動再起動します');
      }
      
      await _speechToText.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (_isContinuousListening && !_isPaused) {
        await _startListening();
        _startRestartTimer();
      }
    } catch (e) {
      onError?.call('自動再起動エラー: $e');
    }
  }

  /// 再起動のスケジュール
  void _scheduleRestart() {
    if (!_isContinuousListening || _restartAttempts >= maxRestartAttempts) return;
    
    _restartTimer?.cancel();
    _restartAttempts++;
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isContinuousListening) {
        _startListening();
      }
    });
  }

  /// 音声レベルのシミュレーション開始
  void _startSoundLevelSimulation() {
    _soundLevelTimer?.cancel();
    _soundLevelTimer = Timer.periodic(_soundLevelUpdateInterval, (timer) {
      if ((_isContinuousListening && !_isPaused) || _isRecording) {
        _soundLevel = _generateRandomSoundLevel();
      } else {
        _soundLevel = 0.0;
        timer.cancel();
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

  /// 録音ファイルの処理
  Future<void> _processRecordedFile(String path) async {
    try {
      // ファイルの存在確認
      final file = File(path);
      final fileExists = await file.exists();
      
      if (!fileExists) {
        onError?.call('録音ファイルが見つかりません: $path');
        return;
      }
      
      // ファイルサイズの確認
      final fileSize = await file.length();
      if (fileSize <= 0) {
        onError?.call('録音ファイルが空です: $path');
        try {
          await file.delete();
        } catch (e) {
          print('空ファイル削除エラー: $e');
        }
        return;
      }
      
      // 録音時間計算
      final duration = DateTime.now().difference(_recordingStartTime!);
      
      // 書き起こしテキストを保存
      final transcriptionText = _recognizedText.isNotEmpty ? _recognizedText : null;
      
      // ボイスメモオブジェクト作成
      final voiceMemo = VoiceMemo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: path,
        title: 'ボイスメモ ${DateTime.now().month}/${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        createdAt: _recordingStartTime!,
        duration: duration,
        transcription: transcriptionText,
      );

      // 保存
      final saveSuccess = await saveVoiceMemo(voiceMemo);
      if (saveSuccess) {
        onVoiceMemoCreated?.call(voiceMemo);
        
        if (transcriptionText != null && transcriptionText.isNotEmpty) {
          onTranscriptionUpdated?.call(transcriptionText);
        }
        
        print('録音を停止しました: $path (サイズ: ${fileSize}バイト)');
        print('書き起こし: ${voiceMemo.transcription ?? "なし"}');
      } else {
        onError?.call('ボイスメモの保存に失敗しました');
      }
    } catch (e) {
      print('録音ファイル処理エラー: $e');
      onError?.call('録音ファイル処理エラー: $e');
    }
  }

  /// 音声認識エラーハンドリング
  void _handleSpeechError(SpeechRecognitionError error) {
    print('音声認識エラー: ${error.errorMsg}');
    
    // error_no_matchは正常な状況（音声が認識されなかった）なので無視
    if (error.errorMsg == 'error_no_match') {
      print('音声が認識されませんでした（正常）');
      return;
    }
    
    // 連続音声認識中の場合、回復可能なエラーは再試行
    if (_isContinuousListening) {
      if (error.errorMsg.contains('network') || 
          error.errorMsg.contains('timeout') || 
          error.errorMsg.contains('audio')) {
        print('回復可能なエラーです。再試行します: ${error.errorMsg}');
        _scheduleRestart();
      } else {
        print('回復不可能なエラー: ${error.errorMsg}');
        onError?.call('音声認識エラー: ${error.errorMsg}');
      }
    } else {
      // 通常の録音中は重要なエラーのみ表示
      if (error.errorMsg != 'error_no_match') {
        onError?.call('音声認識エラー: ${error.errorMsg}');
      }
    }
  }

  /// 音声認識ステータスの処理
  void _handleStatusChange(String status) {
    switch (status) {
      case 'listening':
        onStatusChanged?.call('音声を聞いています...');
        break;
      case 'notListening':
        if (_isContinuousListening && !_isPaused) {
          // 予期しない停止の場合、自動再起動を試行
          _restartListening();
        }
        break;
      case 'done':
        onStatusChanged?.call('音声認識完了');
        break;
      default:
        onStatusChanged?.call(status);
    }
  }

  /// 手動音声メモの作成（連続音声認識用）
  Future<VoiceMemo?> createManualVoiceMemo() async {
    if (_recognizedText.isEmpty) {
      onError?.call('認識されたテキストがありません');
      return null;
    }

    try {
      final voiceMemo = VoiceMemo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Manual音声メモ ${DateTime.now().toString().substring(0, 16)}',
        transcription: _recognizedText,
        filePath: '', // Manual音声認識では音声ファイルは保存されない
        createdAt: DateTime.now(),
        duration: Duration.zero,
      );
      
      final saveSuccess = await saveVoiceMemo(voiceMemo);
      if (saveSuccess) {
        onVoiceMemoCreated?.call(voiceMemo);
        return voiceMemo;
      } else {
        onError?.call('Manual音声メモの保存に失敗しました');
        return null;
      }
    } catch (e) {
      print('Manual音声メモ作成エラー: $e');
      onError?.call('Manual音声メモの作成に失敗しました: $e');
      return null;
    }
  }

  /// ボイスメモ保存
  Future<bool> saveVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      // ファイルパスが指定されている場合は存在確認
      if (voiceMemo.filePath.isNotEmpty) {
        final file = File(voiceMemo.filePath);
        final exists = await file.exists();
        
        if (!exists) {
          print('警告: ボイスメモのファイルが存在しません: ${voiceMemo.filePath}');
          // 書き起こしがある場合は保存を続行
          if (voiceMemo.transcription == null || voiceMemo.transcription!.isEmpty) {
            onError?.call('ボイスメモのファイルが見つかりません: ${voiceMemo.filePath}');
            return false;
          }
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final voiceMemos = await getVoiceMemos();
      voiceMemos.insert(0, voiceMemo);
      
      final voiceMemosJson = voiceMemos.map((memo) => memo.toJson()).toList();
      final success = await prefs.setString('voice_memos', jsonEncode(voiceMemosJson));
      
      if (!success) {
        onError?.call('ボイスメモのメタデータ保存に失敗しました');
        return false;
      }
      
      return true;
    } catch (e) {
      print('ボイスメモ保存エラー詳細: $e');
      onError?.call('ボイスメモ保存エラー: $e');
      return false;
    }
  }

  /// ボイスメモ一覧取得
  Future<List<VoiceMemo>> getVoiceMemos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceMemosString = prefs.getString('voice_memos');
      
      if (voiceMemosString != null) {
        final voiceMemosJson = jsonDecode(voiceMemosString) as List;
        return voiceMemosJson.map((json) => VoiceMemo.fromJson(json)).toList();
      }
      
      return [];
    } catch (e) {
      onError?.call('ボイスメモ読み込みエラー: $e');
      return [];
    }
  }

  /// ボイスメモ削除
  Future<void> deleteVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      // ファイル削除
      if (voiceMemo.filePath.isNotEmpty) {
        final file = File(voiceMemo.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // リストから削除
      final prefs = await SharedPreferences.getInstance();
      final voiceMemos = await getVoiceMemos();
      voiceMemos.removeWhere((memo) => memo.id == voiceMemo.id);
      
      final voiceMemosJson = voiceMemos.map((memo) => memo.toJson()).toList();
      await prefs.setString('voice_memos', jsonEncode(voiceMemosJson));
    } catch (e) {
      onError?.call('ボイスメモ削除エラー: $e');
    }
  }

  /// リソース解放
  void dispose() {
    _isContinuousListening = false;
    _isPaused = false;
    _stopTimers();
    _recorder.dispose();
    _speechToText.cancel();
    _isInitialized = false;
    _recognizedText = '';
    _soundLevel = 0.0;
    
    if (kDebugMode) {
      print('UnifiedVoiceService disposed');
    }
  }
}