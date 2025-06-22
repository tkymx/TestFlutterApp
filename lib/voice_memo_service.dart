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

class VoiceMemo {
  String id;
  String filePath;
  String title;
  DateTime createdAt;
  Duration duration;
  String? transcription; // 音声の書き起こしテキスト

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

class VoiceMemoService {
  static final VoiceMemoService _instance = VoiceMemoService._internal();
  factory VoiceMemoService() => _instance;
  VoiceMemoService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isRecording = false;
  bool _isBackgroundServiceRunning = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  String _recognizedText = '';
  bool _speechEnabled = false;
  bool _isContinuousListening = false;
  Timer? _restartTimer;

  // コールバック
  Function(VoiceMemo)? onVoiceMemoCreated;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;
  Function(String)? onTranscriptionUpdated;

  bool get isRecording => _isRecording;
  bool get isBackgroundServiceRunning => _isBackgroundServiceRunning;

  // 初期化
  Future<bool> initialize() async {
    try {
      print('ボイスメモサービスの初期化を開始します...');
      
      // Webプラットフォームでは制限された機能のみ
      if (kIsWeb) {
        print('Webプラットフォームでは機能制限があります');
        onError?.call('Webプラットフォームではボイスメモ機能は制限されています');
        return false;
      }

      // 権限チェック - 失敗しても続行
      bool permissionsGranted = await _checkPermissions();
      if (!permissionsGranted) {
        print('権限が付与されていません。一部機能が制限される可能性があります');
        // 権限がなくても続行する場合はコメントを外す
        // return false;
      }

      // バックグラウンドサービスの初期化
      await _initializeBackgroundService();
      
      // 録音機能の初期化確認
      bool recorderInitialized = await _initializeRecorder();
      if (!recorderInitialized) {
        print('録音機能の初期化に失敗しました');
        onError?.call('録音機能の初期化に失敗しました');
        return false;
      }
      
      // 音声認識機能の初期化
      _speechEnabled = await _speechToText.initialize();
      if (!_speechEnabled) {
        print('音声認識機能の初期化に失敗しました。書き起こし機能が制限されます');
      } else {
        print('音声認識機能の初期化に成功しました');
      }
      
      print('ボイスメモサービスの初期化が完了しました');
      return true;
    } catch (e) {
      print('初期化エラー: $e');
      onError?.call('初期化エラー: $e');
      return false;
    }
  }
  
  // 録音機能の初期化確認
  Future<bool> _initializeRecorder() async {
    try {
      // 録音機能が利用可能か確認
      final isRecorderInitialized = await _recorder.isEncoderSupported(
        AudioEncoder.aacLc,
      );
      
      print('録音機能初期化状態: $isRecorderInitialized');
      return isRecorderInitialized;
    } catch (e) {
      print('録音機能初期化エラー: $e');
      // エラーが発生しても続行を試みる
      return true;
    }
  }

  // 権限チェック
  Future<bool> _checkPermissions() async {
    if (kIsWeb) return false;

    try {
      // Android 13 (API 33)以降ではストレージ権限が変更されているため、
      // Permission.storageの代わりに適切な権限を使用
      final permissions = [
        Permission.microphone,
      ];
      
      // Android 13未満の場合はストレージ権限も追加
      if (!kIsWeb && Platform.isAndroid) {
        if (int.parse(Platform.version) < 33) {
          permissions.add(Permission.storage);
        } else {
          // Android 13以降では必要に応じて以下の権限を使用
          // permissions.add(Permission.photos);
          // permissions.add(Permission.videos);
          // permissions.add(Permission.audio);
        }
      }

      // 権限リクエスト
      Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      // すべての権限が許可されているか確認
      bool allGranted = statuses.values.every((status) => 
        status == PermissionStatus.granted || 
        status == PermissionStatus.limited);
      
      print('権限チェック結果: $allGranted (${statuses.toString()})');
      return allGranted;
    } catch (e) {
      print('権限チェックエラー: $e');
      // エラーが発生した場合でも処理を続行
      return true;
    }
  }

  // バックグラウンドサービスの初期化
  Future<void> _initializeBackgroundService() async {
    // バックグラウンドサービスは使用しないため空の実装
    return;
  }



  // 音声認識の開始（連続音声認識対応）
  Future<void> _startSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    _isContinuousListening = true;
    _recognizedText = '';
    
    await _startListeningSession();
  }

  // 音声認識セッションの開始
  Future<void> _startListeningSession() async {
    if (!_speechEnabled || !_isContinuousListening) return;
    
    try {
      print('音声認識セッションを開始します');
      
      await _speechToText.listen(
        onResult: (result) {
          _recognizedText = result.recognizedWords;
          // 録音中は書き起こしテキストを更新しない（録音終了後に表示するため）
          // onTranscriptionUpdated?.call(_recognizedText);
          print('認識テキスト: $_recognizedText');
        },
        listenFor: const Duration(seconds: 30), // 30秒ごとに再開
        pauseFor: const Duration(seconds: 2), // 無音許容時間を短縮
        partialResults: true,
        localeId: 'ja_JP',
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        onSoundLevelChange: (level) {
          // 音声レベルの監視（デバッグ用）
          // print('音声レベル: $level');
        },
      );
      
      // 音声認識の状態を監視
      _monitorSpeechRecognition();
      
    } catch (e) {
      print('音声認識セッション開始エラー: $e');
      // エラーが発生した場合、少し待ってから再試行
      if (_isContinuousListening) {
        _scheduleRestart();
      }
    }
  }

  // 音声認識の状態監視
  void _monitorSpeechRecognition() {
    _restartTimer?.cancel();
    _restartTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isContinuousListening) {
        timer.cancel();
        return;
      }
      
      // 音声認識が停止している場合は再開
      if (!_speechToText.isListening) {
        print('音声認識が停止しました。再開します...');
        timer.cancel();
        _scheduleRestart();
      }
    });
  }

  // 音声認識の再開をスケジュール
  void _scheduleRestart() {
    if (!_isContinuousListening) return;
    
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isContinuousListening) {
        _startListeningSession();
      }
    });
  }

  // 音声認識の停止
  Future<void> _stopSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    _isContinuousListening = false;
    _restartTimer?.cancel();
    
    try {
      await _speechToText.stop();
      print('音声認識を停止しました');
    } catch (e) {
      print('音声認識停止エラー: $e');
    }
  }

  // 録音開始
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
      _recognizedText = ''; // 認識テキストをリセット
      onRecordingStateChanged?.call(true);
      
      // 音声認識開始
      await _startSpeechRecognition();
      print('録音を開始しました: $_currentRecordingPath');
    } catch (e) {
      onError?.call('録音開始エラー: $e');
    }
  }

  // 録音停止
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      onRecordingStateChanged?.call(false);
      
      // 音声認識停止
      await _stopSpeechRecognition();

      if (path != null && _recordingStartTime != null) {
        // 録音時間計算
        final duration = DateTime.now().difference(_recordingStartTime!);
        
        // 書き起こしテキストを保存（録音中は表示せず、録音後に表示するため）
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
        await _saveVoiceMemo(voiceMemo);
        onVoiceMemoCreated?.call(voiceMemo);
        
        // 書き起こしテキストがある場合は通知
        if (transcriptionText != null && transcriptionText.isNotEmpty) {
          onTranscriptionUpdated?.call(transcriptionText);
        }
        
        print('録音を停止しました: $path');
        print('書き起こし: ${voiceMemo.transcription ?? "なし"}');
      }

      _currentRecordingPath = null;
      _recordingStartTime = null;
    } catch (e) {
      onError?.call('録音停止エラー: $e');
    }
  }

  // ボイスメモ保存
  Future<void> _saveVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceMemos = await getVoiceMemos();
      voiceMemos.insert(0, voiceMemo);
      
      final voiceMemosJson = voiceMemos.map((memo) => memo.toJson()).toList();
      await prefs.setString('voice_memos', jsonEncode(voiceMemosJson));
    } catch (e) {
      onError?.call('ボイスメモ保存エラー: $e');
    }
  }

  // ボイスメモ一覧取得
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

  // ボイスメモ削除
  Future<void> deleteVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      // ファイル削除
      final file = File(voiceMemo.filePath);
      if (await file.exists()) {
        await file.delete();
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

  // リソース解放
  void dispose() {
    _isContinuousListening = false;
    _restartTimer?.cancel();
    _recorder.dispose();
    _speechToText.cancel();
  }
}

