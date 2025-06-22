import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'voice_memo_service.dart';

/// 改良された音声認識サービス
/// 連続音声認識の問題を解決し、一時停止/再開機能を提供
class ImprovedVoiceService {
  late stt.SpeechToText _speechToText;
  
  // コールバック関数
  Function(String)? onTranscriptionUpdated;
  Function(String)? onError;
  Function(String)? onStatusChanged;
  
  // 状態管理
  bool _isListening = false;
  bool _isPaused = false;
  bool _isInitialized = false;
  String _recognizedText = '';
  double _soundLevel = 0.0;
  
  // タイマー管理
  Timer? _restartTimer;
  Timer? _soundLevelTimer;
  
  // 設定
  static const Duration _restartInterval = Duration(seconds: 50); // 50秒で再起動（プラットフォーム制限を回避）
  static const Duration _soundLevelUpdateInterval = Duration(milliseconds: 100);
  
  // ゲッター
  bool get isListening => _isListening;
  bool get isPaused => _isPaused;
  bool get isInitialized => _isInitialized;
  String get recognizedText => _recognizedText;
  double get soundLevel => _soundLevel;

  /// サービスの初期化
  Future<bool> initialize() async {
    try {
      _speechToText = stt.SpeechToText();
      
      bool available = await _speechToText.initialize(
        onError: (error) {
          _handleError('音声認識エラー: ${error.errorMsg}');
        },
        onStatus: (status) {
          _handleStatusChange(status);
        },
      );
      
      if (available) {
        _isInitialized = true;
        _updateStatus('初期化完了');
        return true;
      } else {
        _handleError('音声認識が利用できません');
        return false;
      }
    } catch (e) {
      _handleError('初期化エラー: $e');
      return false;
    }
  }

  /// 連続音声認識の開始
  Future<void> startContinuousListening() async {
    if (!_isInitialized) {
      _handleError('サービスが初期化されていません');
      return;
    }

    if (_isListening) {
      _updateStatus('既に録音中です');
      return;
    }

    try {
      _isListening = true;
      _isPaused = false;
      _recognizedText = '';
      
      await _startListening();
      _startRestartTimer();
      _startSoundLevelSimulation();
      
      _updateStatus('連続録音開始');
    } catch (e) {
      _handleError('録音開始エラー: $e');
      _isListening = false;
    }
  }

  /// 音声認識の一時停止
  Future<void> pauseListening() async {
    if (!_isListening || _isPaused) {
      return;
    }

    try {
      _isPaused = true;
      await _speechToText.stop();
      _stopTimers();
      _updateStatus('一時停止中');
    } catch (e) {
      _handleError('一時停止エラー: $e');
    }
  }

  /// 音声認識の再開
  Future<void> resumeListening() async {
    if (!_isListening || !_isPaused) {
      return;
    }

    try {
      _isPaused = false;
      await _startListening();
      _startRestartTimer();
      _startSoundLevelSimulation();
      _updateStatus('録音再開');
    } catch (e) {
      _handleError('再開エラー: $e');
    }
  }

  /// 音声認識の停止
  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    try {
      _isListening = false;
      _isPaused = false;
      await _speechToText.stop();
      _stopTimers();
      _soundLevel = 0.0;
      _updateStatus('録音停止');
    } catch (e) {
      _handleError('停止エラー: $e');
    }
  }

  /// 実際の音声認識開始
  Future<void> _startListening() async {
    await _speechToText.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          _recognizedText = result.recognizedWords;
          onTranscriptionUpdated?.call(_recognizedText);
        }
      },
      listenFor: const Duration(seconds: 60), // 最大60秒
      pauseFor: const Duration(seconds: 3),   // 3秒の無音で一時停止
      partialResults: true,
      localeId: 'ja_JP',
      listenMode: stt.ListenMode.confirmation,
    );
  }

  /// 自動再起動タイマーの開始
  void _startRestartTimer() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartInterval, () {
      if (_isListening && !_isPaused) {
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
      
      if (_isListening && !_isPaused) {
        await _startListening();
        _startRestartTimer();
      }
    } catch (e) {
      _handleError('自動再起動エラー: $e');
    }
  }

  /// 音声レベルのシミュレーション開始
  void _startSoundLevelSimulation() {
    _soundLevelTimer?.cancel();
    _soundLevelTimer = Timer.periodic(_soundLevelUpdateInterval, (timer) {
      if (_isListening && !_isPaused) {
        // 音声レベルをシミュレート（実際の実装では音声入力レベルを取得）
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
    // 0.0 から 1.0 の間でランダムな値を生成
    // 実際の実装では、マイクからの音声レベルを取得する
    return random.nextDouble() * 0.8 + 0.1; // 0.1 から 0.9 の範囲
  }

  /// タイマーの停止
  void _stopTimers() {
    _restartTimer?.cancel();
    _soundLevelTimer?.cancel();
  }

  /// エラーハンドリング
  void _handleError(String error) {
    if (kDebugMode) {
      print('ImprovedVoiceService Error: $error');
    }
    onError?.call(error);
  }

  /// ステータス更新
  void _updateStatus(String status) {
    if (kDebugMode) {
      print('ImprovedVoiceService Status: $status');
    }
    onStatusChanged?.call(status);
  }

  /// 音声認識ステータスの処理
  void _handleStatusChange(String status) {
    switch (status) {
      case 'listening':
        _updateStatus('音声を聞いています...');
        break;
      case 'notListening':
        if (_isListening && !_isPaused) {
          // 予期しない停止の場合、自動再起動を試行
          _restartListening();
        }
        break;
      case 'done':
        _updateStatus('音声認識完了');
        break;
      default:
        _updateStatus(status);
    }
  }

  /// リソースの解放
  void dispose() {
    _stopTimers();
    _isListening = false;
    _isPaused = false;
    _isInitialized = false;
    _recognizedText = '';
    _soundLevel = 0.0;
    
    if (kDebugMode) {
      print('ImprovedVoiceService disposed');
    }
  }
}