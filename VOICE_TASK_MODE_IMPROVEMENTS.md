# ボイスタスクモード改善実装

## 問題の原因

ボイスタスクモードで途中で止まってしまう問題の主な原因は以下の通りです：

### 1. speech_to_textライブラリの制限
- **Androidの制限**: 通常10秒程度で自動タイムアウト
- **iOSの制限**: 1分の制限
- **無音検知**: 3秒の無音で自動停止
- **プラットフォーム固有の制限**: ネットワークベースのサービスのため、デバイスやOSバージョンによる制限

### 2. 現在の設定の問題
```dart
// 問題のある設定
listenFor: const Duration(minutes: 30), // 実際には無効
pauseFor: const Duration(seconds: 3),   // 3秒で停止
```

## 実装した解決策

### 1. 標準サービスの改善 (voice_memo_service.dart)

#### 連続音声認識の実装
```dart
// 連続音声認識のための新しい変数
bool _isContinuousListening = false;
Timer? _restartTimer;

// 改善された音声認識設定
await _speechToText.listen(
  listenFor: const Duration(seconds: 30), // 30秒ごとに再開
  pauseFor: const Duration(seconds: 2),   // 無音許容時間を短縮
  partialResults: true,
  localeId: 'ja_JP',
  cancelOnError: false,
  listenMode: stt.ListenMode.dictation,
);
```

#### 自動再開メカニズム
```dart
// 音声認識の状態監視
void _monitorSpeechRecognition() {
  _restartTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (!_speechToText.isListening) {
      print('音声認識が停止しました。再開します...');
      _scheduleRestart();
    }
  });
}

// 自動再開のスケジューリング
void _scheduleRestart() {
  _restartTimer = Timer(const Duration(milliseconds: 500), () {
    if (_isContinuousListening) {
      _startListeningSession();
    }
  });
}
```

### 2. 拡張音声サービスの実装 (enhanced_voice_service.dart)

#### より安定した音声処理
- **Flutter Sound**: より高機能な音声録音ライブラリを使用
- **Wakelock**: 画面スリープ防止で安定性向上
- **エラーハンドリング**: 回復可能なエラーの自動再試行

#### 高度な連続音声認識
```dart
// Keep-alive タイマーによる監視
void _startKeepAliveTimer() {
  _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
    if (!_speechToText.isListening && _isRecording) {
      print('Keep-alive: 音声認識が停止しています。再開します...');
      _restartListeningSession();
    }
  });
}

// インテリジェントな再試行メカニズム
void _restartListeningSession() {
  if (_restartAttempts >= maxRestartAttempts) {
    print('最大再試行回数に達しました。音声認識を停止します。');
    return;
  }
  
  _restartAttempts++;
  Timer(const Duration(milliseconds: 300), () {
    if (_isContinuousListening) {
      _startListeningSession();
    }
  });
}
```

#### エラー分類と対応
```dart
void _handleSpeechError(String errorMsg) {
  // 回復可能なエラーの判定
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
```

### 3. UIの改善

#### サービス自動選択
```dart
// 拡張サービスを優先的に使用
bool enhancedSuccess = await _enhancedVoiceService.initialize();

if (enhancedSuccess) {
  _useEnhancedService = true;
  _setupEnhancedServiceCallbacks();
} else {
  // フォールバックとして標準サービスを使用
  bool standardSuccess = await _voiceMemoService.initialize();
  if (standardSuccess) {
    _setupStandardServiceCallbacks();
  }
}
```

#### 状態表示の改善
- 拡張版使用時の視覚的表示
- リアルタイム状態更新
- エラー状況の詳細表示

## 新しい依存関係

```yaml
dependencies:
  # 既存のライブラリ
  speech_to_text: ^7.0.0
  record: ^5.1.2
  
  # 新しく追加
  flutter_sound: ^9.2.13      # より高機能な音声処理
  wakelock_plus: ^1.2.8       # 画面スリープ防止
```

## 技術的改善点

### 1. 連続音声認識の実現
- **25-30秒ごとの自動再開**: プラットフォーム制限を回避
- **Keep-aliveメカニズム**: 5秒ごとの状態監視
- **インテリジェントな再試行**: 最大5回まで自動再試行

### 2. エラー処理の強化
- **エラー分類**: 回復可能/不可能なエラーの判定
- **段階的フォールバック**: 拡張版→標準版→エラー表示
- **ユーザーフィードバック**: 詳細な状態情報の提供

### 3. パフォーマンス最適化
- **リソース管理**: 適切なタイマーとリスナーの管理
- **メモリ効率**: 不要なリソースの自動解放
- **バッテリー最適化**: Wakelockの適切な使用

## 使用方法

### 1. 自動サービス選択
アプリ起動時に自動的に最適なサービスが選択されます：
- 拡張音声サービスが利用可能な場合は優先使用
- 失敗した場合は標準サービスにフォールバック

### 2. 連続音声認識
録音開始後、以下の機能が自動的に動作します：
- 25-30秒ごとの音声認識セッション再開
- エラー発生時の自動再試行
- 音声レベル監視による最適化

### 3. 状態監視
UIで以下の情報を確認できます：
- 使用中のサービス（標準版/拡張版）
- リアルタイム状態更新
- エラー発生時の詳細情報

## 期待される改善効果

### 1. 安定性の向上
- **連続録音時間**: 理論上無制限（実際は端末性能による）
- **エラー回復**: 自動的なエラー回復により中断の大幅減少
- **プラットフォーム対応**: Android/iOS両方での安定動作

### 2. ユーザビリティの向上
- **透明性**: 現在の状態が明確に表示
- **信頼性**: 予期しない停止の大幅減少
- **フィードバック**: 問題発生時の詳細情報提供

### 3. 技術的優位性
- **最新技術**: Flutter Soundによる高品質録音
- **効率性**: 適切なリソース管理
- **拡張性**: 将来的な機能追加への対応

## 今後の拡張可能性

1. **オフライン音声認識**: ローカル音声認識エンジンの統合
2. **クラウド音声認識**: Google Cloud Speech-to-Text APIの統合
3. **音声品質向上**: ノイズキャンセリング機能
4. **多言語対応**: 複数言語での音声認識
5. **音声コマンド**: 音声による操作制御

## 注意事項

1. **権限要求**: マイクとストレージの権限が必要
2. **バッテリー消費**: 連続音声認識によるバッテリー消費増加
3. **ネットワーク使用**: 音声認識にはインターネット接続が必要
4. **プライバシー**: 音声データの適切な管理が重要