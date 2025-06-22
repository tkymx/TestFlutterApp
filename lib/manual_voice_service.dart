import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:manual_speech_to_text/manual_speech_to_text.dart';
import 'voice_memo_service.dart';

/// Manual Speech-to-Text を使用した高度な音声認識サービス
/// 真の連続音声認識、一時停止/再開機能を提供
class ManualVoiceService {
  late ManualSttController _controller;
  
  // コールバック関数
  Function(String)? onTranscriptionUpdated;
  Function(String)? onError;
  Function(String)? onStatusChanged;
  
  // 状態管理
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isPaused = false;
  String _recognizedText = '';
  ManualSttState _currentState = ManualSttState.stopped;
  double _soundLevel = 0.0;
  
  // 設定
  String _localeId = 'ja-JP';
  bool _enableHapticFeedback = true;
  bool _clearTextOnStart = false;
  Duration _pauseIfMuteFor = const Duration(seconds: 10);
  
  // ゲッター
  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isPaused => _isPaused;
  String get recognizedText => _recognizedText;
  ManualSttState get currentState => _currentState;
  double get soundLevel => _soundLevel;
  
  /// サービスの初期化
  Future<bool> initialize() async {
    try {
      print('ManualVoiceService: 初期化開始');
      
      _controller = ManualSttController();
      _setupController();
      
      _isInitialized = true;
      print('ManualVoiceService: 初期化完了');
      onStatusChanged?.call('初期化完了');
      
      return true;
    } catch (e) {
      print('ManualVoiceService: 初期化エラー - $e');
      onError?.call('初期化に失敗しました: $e');
      return false;
    }
  }
  
  /// コントローラーの設定
  void _setupController() {
    // 基本設定
    _controller.localId = _localeId;
    _controller.enableHapticFeedback = _enableHapticFeedback;
    _controller.clearTextOnStart = _clearTextOnStart;
    _controller.pauseIfMuteFor = _pauseIfMuteFor;
    
    // リスナーの設定
    _controller.listen(
      onListeningStateChanged: _onStateChanged,
      onListeningTextChanged: _onTextChanged,
      onSoundLevelChanged: _onSoundLevelChanged,
    );
    
    // 権限拒否時の処理
    _controller.handlePermanentlyDeniedPermission(() {
      onError?.call('マイクの権限が拒否されました。設定から権限を有効にしてください。');
    });
    
    // カスタム権限ダイアログ
    _controller.permanentDenialDialogTitle = 'マイクアクセスが必要です';
    _controller.permanentDenialDialogContent = '音声認識機能を使用するにはマイクの権限が必要です。';
  }
  
  /// 状態変更のコールバック
  void _onStateChanged(ManualSttState state) {
    print('ManualVoiceService: 状態変更 - ${state.name}');
    
    _currentState = state;
    
    switch (state) {
      case ManualSttState.listening:
        _isListening = true;
        _isPaused = false;
        onStatusChanged?.call('音声認識中');
        break;
      case ManualSttState.paused:
        _isListening = false;
        _isPaused = true;
        onStatusChanged?.call('一時停止中');
        break;
      case ManualSttState.stopped:
        _isListening = false;
        _isPaused = false;
        onStatusChanged?.call('停止');
        break;
    }
  }
  
  /// テキスト変更のコールバック
  void _onTextChanged(String text) {
    print('ManualVoiceService: テキスト更新 - $text');
    
    _recognizedText = text;
    onTranscriptionUpdated?.call(text);
  }
  
  /// 音声レベル変更のコールバック
  void _onSoundLevelChanged(double level) {
    _soundLevel = level;
    // 音声レベルは頻繁に更新されるため、ログは出力しない
  }
  
  /// 連続音声認識の開始
  Future<void> startContinuousListening() async {
    if (!_isInitialized) {
      onError?.call('サービスが初期化されていません');
      return;
    }
    
    try {
      print('ManualVoiceService: 連続音声認識開始');
      await _controller.startStt();
      onStatusChanged?.call('連続音声認識を開始しました');
    } catch (e) {
      print('ManualVoiceService: 開始エラー - $e');
      onError?.call('音声認識の開始に失敗しました: $e');
    }
  }
  
  /// 音声認識の一時停止
  Future<void> pauseListening() async {
    if (!_isListening) {
      onError?.call('音声認識が実行されていません');
      return;
    }
    
    try {
      print('ManualVoiceService: 音声認識一時停止');
      await _controller.pauseStt();
      onStatusChanged?.call('音声認識を一時停止しました');
    } catch (e) {
      print('ManualVoiceService: 一時停止エラー - $e');
      onError?.call('音声認識の一時停止に失敗しました: $e');
    }
  }
  
  /// 音声認識の再開
  Future<void> resumeListening() async {
    if (!_isPaused) {
      onError?.call('音声認識が一時停止されていません');
      return;
    }
    
    try {
      print('ManualVoiceService: 音声認識再開');
      await _controller.resumeStt();
      onStatusChanged?.call('音声認識を再開しました');
    } catch (e) {
      print('ManualVoiceService: 再開エラー - $e');
      onError?.call('音声認識の再開に失敗しました: $e');
    }
  }
  
  /// 音声認識の停止
  Future<void> stopListening() async {
    if (!_isListening && !_isPaused) {
      return; // 既に停止している
    }
    
    try {
      print('ManualVoiceService: 音声認識停止');
      await _controller.stopStt();
      onStatusChanged?.call('音声認識を停止しました');
    } catch (e) {
      print('ManualVoiceService: 停止エラー - $e');
      onError?.call('音声認識の停止に失敗しました: $e');
    }
  }
  
  /// ボイスメモの録音と保存
  Future<VoiceMemo?> recordVoiceMemo(String title) async {
    if (!_isInitialized) {
      onError?.call('サービスが初期化されていません');
      return null;
    }
    
    try {
      // 連続音声認識を開始
      await startContinuousListening();
      
      // 録音完了まで待機（ユーザーが停止するまで）
      while (_isListening || _isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // 認識されたテキストでボイスメモを作成
      if (_recognizedText.isNotEmpty) {
        final voiceMemo = VoiceMemo(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title.isNotEmpty ? title : '音声メモ ${DateTime.now().toString().substring(0, 16)}',
          transcription: _recognizedText,
          filePath: '', // manual_speech_to_textは音声ファイルを保存しない
          createdAt: DateTime.now(),
          duration: Duration.zero, // 継続時間は計算できない
        );
        
        print('ManualVoiceService: ボイスメモ作成完了 - ${voiceMemo.title}');
        return voiceMemo;
      } else {
        onError?.call('音声が認識されませんでした');
        return null;
      }
    } catch (e) {
      print('ManualVoiceService: 録音エラー - $e');
      onError?.call('録音中にエラーが発生しました: $e');
      return null;
    }
  }
  
  /// 設定の更新
  void updateSettings({
    String? localeId,
    bool? enableHapticFeedback,
    bool? clearTextOnStart,
    Duration? pauseIfMuteFor,
  }) {
    if (localeId != null) _localeId = localeId;
    if (enableHapticFeedback != null) _enableHapticFeedback = enableHapticFeedback;
    if (clearTextOnStart != null) _clearTextOnStart = clearTextOnStart;
    if (pauseIfMuteFor != null) _pauseIfMuteFor = pauseIfMuteFor;
    
    // 設定を再適用
    if (_isInitialized) {
      _setupController();
    }
  }
  
  /// 認識テキストのクリア
  void clearRecognizedText() {
    _recognizedText = '';
    onTranscriptionUpdated?.call('');
  }
  
  /// リソースの解放
  void dispose() {
    print('ManualVoiceService: リソース解放');
    
    try {
      if (_isListening || _isPaused) {
        _controller.stopStt();
      }
      _controller.dispose();
    } catch (e) {
      print('ManualVoiceService: 解放エラー - $e');
    }
    
    _isInitialized = false;
    _isListening = false;
    _isPaused = false;
    _recognizedText = '';
    _currentState = ManualSttState.stopped;
    _soundLevel = 0.0;
  }
  
  /// デバッグ情報の取得
  Map<String, dynamic> getDebugInfo() {
    return {
      'isInitialized': _isInitialized,
      'isListening': _isListening,
      'isPaused': _isPaused,
      'currentState': _currentState.name,
      'recognizedText': _recognizedText,
      'soundLevel': _soundLevel,
      'localeId': _localeId,
      'enableHapticFeedback': _enableHapticFeedback,
      'clearTextOnStart': _clearTextOnStart,
      'pauseIfMuteFor': _pauseIfMuteFor.inSeconds,
    };
  }
}