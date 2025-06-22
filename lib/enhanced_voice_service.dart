import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'voice_memo_service.dart';

/// 拡張音声認識サービス
/// 連続音声認識とより安定した録音機能を提供
class EnhancedVoiceService {
  static final EnhancedVoiceService _instance = EnhancedVoiceService._internal();
  factory EnhancedVoiceService() => _instance;
  EnhancedVoiceService._internal();

  // Flutter Sound
  FlutterSoundRecorder? _soundRecorder;
  FlutterSoundPlayer? _soundPlayer;
  
  // Speech to Text
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  
  // 状態管理
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _speechEnabled = false;
  bool _isContinuousListening = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  String _recognizedText = '';
  
  // 連続音声認識用
  Timer? _restartTimer;
  Timer? _keepAliveTimer;
  int _restartAttempts = 0;
  static const int maxRestartAttempts = 5;
  
  // コールバック
  Function(VoiceMemo)? onVoiceMemoCreated;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;
  Function(String)? onTranscriptionUpdated;
  Function(String)? onStatusChanged;

  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;
  bool get isContinuousListening => _isContinuousListening;

  /// サービスの初期化
  Future<bool> initialize() async {
    try {
      print('拡張音声サービスの初期化を開始します...');
      
      if (kIsWeb) {
        print('Webプラットフォームでは機能制限があります');
        onError?.call('Webプラットフォームでは拡張音声機能は制限されています');
        return false;
      }

      // 権限チェック
      bool permissionsGranted = await _checkPermissions();
      if (!permissionsGranted) {
        print('権限が付与されていません');
        onError?.call('マイクの権限が必要です');
        return false;
      }

      // Flutter Sound の初期化
      await _initializeFlutterSound();
      
      // Speech to Text の初期化
      _speechEnabled = await _speechToText.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
      
      if (!_speechEnabled) {
        print('音声認識機能の初期化に失敗しました');
        onError?.call('音声認識機能の初期化に失敗しました');
        return false;
      }

      _isInitialized = true;
      print('拡張音声サービスの初期化が完了しました');
      return true;
    } catch (e) {
      print('初期化エラー: $e');
      onError?.call('初期化エラー: $e');
      return false;
    }
  }

  /// Flutter Sound の初期化
  Future<void> _initializeFlutterSound() async {
    _soundRecorder = FlutterSoundRecorder();
    _soundPlayer = FlutterSoundPlayer();
    
    await _soundRecorder!.openRecorder();
    await _soundPlayer!.openPlayer();
    
    print('Flutter Sound の初期化が完了しました');
  }

  /// 権限チェック
  Future<bool> _checkPermissions() async {
    if (kIsWeb) return false;

    try {
      final permissions = [
        Permission.microphone,
      ];
      
      if (!kIsWeb && Platform.isAndroid) {
        permissions.add(Permission.storage);
      }

      Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      bool allGranted = statuses.values.every((status) => 
        status == PermissionStatus.granted || 
        status == PermissionStatus.limited);
      
      print('権限チェック結果: $allGranted');
      return allGranted;
    } catch (e) {
      print('権限チェックエラー: $e');
      return false;
    }
  }

  /// 録音開始（拡張版）
  Future<void> startRecording() async {
    if (_isRecording || !_isInitialized || kIsWeb) return;

    try {
      // ファイルパス生成
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'enhanced_voice_memo_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordingPath = '${directory.path}/$fileName';

      // Wakelock を有効にして画面スリープを防止
      await WakelockPlus.enable();

      // Flutter Sound で録音開始
      await _soundRecorder!.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recognizedText = '';
      _restartAttempts = 0;
      
      onRecordingStateChanged?.call(true);
      onStatusChanged?.call('録音開始');
      
      // 連続音声認識開始
      await _startContinuousSpeechRecognition();
      
      print('拡張録音を開始しました: $_currentRecordingPath');
    } catch (e) {
      print('録音開始エラー: $e');
      onError?.call('録音開始エラー: $e');
    }
  }

  /// 録音停止（拡張版）
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      // 連続音声認識停止
      await _stopContinuousSpeechRecognition();
      
      // Flutter Sound で録音停止
      final path = await _soundRecorder!.stopRecorder();
      
      // Wakelock を無効化
      await WakelockPlus.disable();
      
      _isRecording = false;
      onRecordingStateChanged?.call(false);
      onStatusChanged?.call('録音停止');

      if (path != null && _recordingStartTime != null) {
        // 録音時間計算
        final duration = DateTime.now().difference(_recordingStartTime!);
        
        // ボイスメモオブジェクト作成
        final voiceMemo = VoiceMemo(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          filePath: path,
          title: '拡張ボイスメモ ${DateTime.now().month}/${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          createdAt: _recordingStartTime!,
          duration: duration,
          transcription: _recognizedText.isNotEmpty ? _recognizedText : null,
        );

        // 保存
        await _saveVoiceMemo(voiceMemo);
        onVoiceMemoCreated?.call(voiceMemo);
        
        print('拡張録音を停止しました: $path');
        print('書き起こし: ${voiceMemo.transcription ?? "なし"}');
      }

      _currentRecordingPath = null;
      _recordingStartTime = null;
    } catch (e) {
      print('録音停止エラー: $e');
      onError?.call('録音停止エラー: $e');
    }
  }

  /// 連続音声認識開始
  Future<void> _startContinuousSpeechRecognition() async {
    if (!_speechEnabled) return;
    
    _isContinuousListening = true;
    _restartAttempts = 0;
    
    // Keep-alive タイマーを開始
    _startKeepAliveTimer();
    
    await _startListeningSession();
  }

  /// 音声認識セッション開始
  Future<void> _startListeningSession() async {
    if (!_speechEnabled || !_isContinuousListening) return;
    
    try {
      print('音声認識セッションを開始します (試行: ${_restartAttempts + 1})');
      
      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 25), // 25秒で区切る
        pauseFor: const Duration(seconds: 1), // 無音許容時間を短縮
        partialResults: true,
        localeId: 'ja_JP',
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        onSoundLevelChange: (level) {
          // 音声レベルの監視
          if (level > 0.1) {
            // 音声が検出された場合、再試行カウンターをリセット
            _restartAttempts = 0;
          }
        },
      );
      
      // 自動再開タイマーを設定
      _scheduleAutoRestart();
      
    } catch (e) {
      print('音声認識セッション開始エラー: $e');
      _handleSpeechError(e.toString());
    }
  }

  /// 自動再開タイマー
  void _scheduleAutoRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 26), () {
      if (_isContinuousListening && _isRecording) {
        print('音声認識セッションを自動再開します');
        _restartListeningSession();
      }
    });
  }

  /// Keep-alive タイマー
  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isContinuousListening) {
        timer.cancel();
        return;
      }
      
      // 音声認識が停止している場合は再開
      if (!_speechToText.isListening && _isRecording) {
        print('Keep-alive: 音声認識が停止しています。再開します...');
        _restartListeningSession();
      }
    });
  }

  /// 音声認識セッション再開
  void _restartListeningSession() {
    if (!_isContinuousListening || _restartAttempts >= maxRestartAttempts) {
      if (_restartAttempts >= maxRestartAttempts) {
        print('最大再試行回数に達しました。音声認識を停止します。');
        onError?.call('音声認識の再開に失敗しました。録音は継続されます。');
      }
      return;
    }
    
    _restartAttempts++;
    
    // 少し待ってから再開
    Timer(const Duration(milliseconds: 300), () {
      if (_isContinuousListening) {
        _startListeningSession();
      }
    });
  }

  /// 連続音声認識停止
  Future<void> _stopContinuousSpeechRecognition() async {
    _isContinuousListening = false;
    _restartTimer?.cancel();
    _keepAliveTimer?.cancel();
    
    try {
      await _speechToText.stop();
      print('連続音声認識を停止しました');
    } catch (e) {
      print('音声認識停止エラー: $e');
    }
  }

  /// 音声認識結果のコールバック
  void _onSpeechResult(SpeechRecognitionResult result) {
    _recognizedText = result.recognizedWords;
    onTranscriptionUpdated?.call(_recognizedText);
    print('認識テキスト: $_recognizedText');
    
    // 結果が確定した場合、再試行カウンターをリセット
    if (result.finalResult) {
      _restartAttempts = 0;
    }
  }

  /// 音声認識状態のコールバック
  void _onSpeechStatus(String status) {
    print('音声認識状態: $status');
    onStatusChanged?.call('音声認識: $status');
    
    if (status == 'done' && _isContinuousListening) {
      // 音声認識が完了した場合、自動的に再開
      Timer(const Duration(milliseconds: 100), () {
        if (_isContinuousListening) {
          _restartListeningSession();
        }
      });
    }
  }

  /// 音声認識エラーのコールバック
  void _onSpeechError(SpeechRecognitionError error) {
    print('音声認識エラー: ${error.errorMsg}');
    _handleSpeechError(error.errorMsg);
  }

  /// 音声認識エラーハンドリング
  void _handleSpeechError(String errorMsg) {
    if (!_isContinuousListening) return;
    
    // 特定のエラーの場合は再試行
    if (errorMsg.contains('network') || 
        errorMsg.contains('timeout') || 
        errorMsg.contains('audio')) {
      print('回復可能なエラーです。再試行します: $errorMsg');
      _restartListeningSession();
    } else {
      print('回復不可能なエラー: $errorMsg');
      onError?.call('音声認識エラー: $errorMsg');
    }
  }

  /// ボイスメモ保存
  Future<void> _saveVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceMemos = await getVoiceMemos();
      voiceMemos.insert(0, voiceMemo);
      
      final voiceMemosJson = voiceMemos.map((memo) => memo.toJson()).toList();
      await prefs.setString('enhanced_voice_memos', jsonEncode(voiceMemosJson));
    } catch (e) {
      print('ボイスメモ保存エラー: $e');
      onError?.call('ボイスメモ保存エラー: $e');
    }
  }

  /// ボイスメモ一覧取得
  Future<List<VoiceMemo>> getVoiceMemos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceMemosString = prefs.getString('enhanced_voice_memos');
      
      if (voiceMemosString != null) {
        final voiceMemosJson = jsonDecode(voiceMemosString) as List;
        return voiceMemosJson.map((json) => VoiceMemo.fromJson(json)).toList();
      }
      
      return [];
    } catch (e) {
      print('ボイスメモ読み込みエラー: $e');
      onError?.call('ボイスメモ読み込みエラー: $e');
      return [];
    }
  }

  /// ボイスメモ削除
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
      await prefs.setString('enhanced_voice_memos', jsonEncode(voiceMemosJson));
    } catch (e) {
      print('ボイスメモ削除エラー: $e');
      onError?.call('ボイスメモ削除エラー: $e');
    }
  }

  /// リソース解放
  void dispose() {
    _isContinuousListening = false;
    _restartTimer?.cancel();
    _keepAliveTimer?.cancel();
    
    _soundRecorder?.closeRecorder();
    _soundPlayer?.closePlayer();
    _speechToText.cancel();
    
    WakelockPlus.disable();
  }
}