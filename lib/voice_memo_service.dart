import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'dart:convert';

class VoiceMemo {
  String id;
  String filePath;
  String title;
  DateTime createdAt;
  Duration duration;

  VoiceMemo({
    required this.id,
    required this.filePath,
    required this.title,
    required this.createdAt,
    this.duration = Duration.zero,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'duration': duration.inMilliseconds,
    };
  }

  factory VoiceMemo.fromJson(Map<String, dynamic> json) {
    return VoiceMemo(
      id: json['id'],
      filePath: json['filePath'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      duration: Duration(milliseconds: json['duration'] ?? 0),
    );
  }
}

class VoiceMemoService {
  static final VoiceMemoService _instance = VoiceMemoService._internal();
  factory VoiceMemoService() => _instance;
  VoiceMemoService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  bool _isRecording = false;
  bool _isBackgroundServiceRunning = false;
  bool _shakeDetectionEnabled = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  
  // 振動検知のパラメータ
  static const double _shakeThreshold = 15.0;
  static const int _shakeTimeWindow = 500; // ミリ秒
  List<double> _accelerationHistory = [];
  DateTime _lastShakeTime = DateTime.now();

  // コールバック
  Function(VoiceMemo)? onVoiceMemoCreated;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;

  bool get isRecording => _isRecording;
  bool get isBackgroundServiceRunning => _isBackgroundServiceRunning;
  bool get shakeDetectionEnabled => _shakeDetectionEnabled;

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
    if (kIsWeb) return;

    try {
      final service = FlutterBackgroundService();
      
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'voice_memo_channel',
          initialNotificationTitle: 'ボイスメモ',
          initialNotificationContent: '振動検知待機中...',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );
      
      print('バックグラウンドサービスの初期化に成功しました');
    } catch (e) {
      print('バックグラウンドサービスの初期化エラー: $e');
      // エラーが発生しても続行できるようにする
    }
  }

  // 振動検知の開始
  Future<void> startShakeDetection() async {
    if (kIsWeb || _shakeDetectionEnabled) return;

    try {
      _shakeDetectionEnabled = true;
      
      // バックグラウンドサービス開始
      await FlutterBackgroundService().startService();
      _isBackgroundServiceRunning = true;

      // 加速度センサーの監視開始
      _accelerometerSubscription = accelerometerEvents.listen(_onAccelerometerEvent);
      
      print('振動検知を開始しました');
    } catch (e) {
      onError?.call('振動検知開始エラー: $e');
      _shakeDetectionEnabled = false;
    }
  }

  // 振動検知の停止
  Future<void> stopShakeDetection() async {
    if (!_shakeDetectionEnabled) return;

    try {
      _shakeDetectionEnabled = false;
      
      // 加速度センサーの監視停止
      await _accelerometerSubscription?.cancel();
      _accelerometerSubscription = null;
      
      // バックグラウンドサービス停止
      FlutterBackgroundService().invoke('stop');
      _isBackgroundServiceRunning = false;
      
      print('振動検知を停止しました');
    } catch (e) {
      onError?.call('振動検知停止エラー: $e');
    }
  }

  // 加速度センサーイベント処理
  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!_shakeDetectionEnabled) return;

    final acceleration = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z
    );

    final now = DateTime.now();
    
    // 履歴に追加
    _accelerationHistory.add(acceleration);
    
    // 古いデータを削除（時間窓を超えたもの）
    _accelerationHistory.removeWhere((value) => 
      now.difference(_lastShakeTime).inMilliseconds > _shakeTimeWindow
    );

    // 振動検知
    if (acceleration > _shakeThreshold && 
        now.difference(_lastShakeTime).inMilliseconds > _shakeTimeWindow) {
      
      _lastShakeTime = now;
      _onShakeDetected();
    }
  }

  // 振動検知時の処理
  void _onShakeDetected() {
    print('振動を検知しました！');
    
    if (_isRecording) {
      // 録音中の場合は停止
      stopRecording();
    } else {
      // 録音していない場合は開始
      startRecording();
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
      onRecordingStateChanged?.call(true);
      
      // バックグラウンドサービスに通知
      FlutterBackgroundService().invoke('recording_started');
      
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

      if (path != null && _recordingStartTime != null) {
        // 録音時間計算
        final duration = DateTime.now().difference(_recordingStartTime!);
        
        // ボイスメモオブジェクト作成
        final voiceMemo = VoiceMemo(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          filePath: path,
          title: 'ボイスメモ ${DateTime.now().month}/${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          createdAt: _recordingStartTime!,
          duration: duration,
        );

        // 保存
        await _saveVoiceMemo(voiceMemo);
        onVoiceMemoCreated?.call(voiceMemo);
        
        // バックグラウンドサービスに通知
        FlutterBackgroundService().invoke('recording_stopped');
        
        print('録音を停止しました: $path');
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
    _accelerometerSubscription?.cancel();
    _recorder.dispose();
  }
}

// バックグラウンドサービスのエントリーポイント
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((event) {
      service.stopSelf();
    });

    service.on('recording_started').listen((event) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'ボイスメモ',
          content: '録音中...',
        );
      }
    });

    service.on('recording_stopped').listen((event) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'ボイスメモ',
          content: '振動検知待機中...',
        );
      }
    });
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}