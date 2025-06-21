# ボイスメモ機能の実装

## 概要
端末を振ることでボイスメモの録音を開始/停止できる機能を実装しました。バックグラウンドでも動作し、アプリが閉じられていても振動検知が可能です。

## 実装した機能

### 1. 振動検知機能
- **加速度センサー**: `sensors_plus`パッケージを使用
- **振動閾値**: 15.0G以上の加速度で振動を検知
- **時間窓**: 500ms以内の連続振動は無視（誤検知防止）
- **バックグラウンド動作**: アプリが非アクティブでも振動検知が継続

### 2. 音声録音機能
- **録音形式**: AAC-LC形式（.m4a）
- **音質**: 44.1kHz、128kbps
- **ファイル保存**: アプリのドキュメントディレクトリに保存
- **自動命名**: 日時ベースの自動ファイル名生成

### 3. バックグラウンドサービス
- **フォアグラウンドサービス**: Android通知領域に常駐
- **権限管理**: マイク、ストレージ、バックグラウンド実行権限
- **通知表示**: 録音状態に応じた通知内容の更新

### 4. ボイスメモ管理
- **一覧表示**: 録音したボイスメモの時系列表示
- **再生機能**: タップで再生/一時停止
- **削除機能**: 長押しまたはボタンで削除
- **メタデータ**: 録音日時、長さの表示

## ファイル構成

### 新規追加ファイル
1. **`lib/voice_memo_service.dart`**
   - ボイスメモの核となるサービスクラス
   - 振動検知、録音、バックグラウンド処理を管理

2. **`lib/voice_memo_page.dart`**
   - ボイスメモのUI画面
   - 録音コントロール、一覧表示、再生機能

### 修正ファイル
1. **`lib/main.dart`**
   - タブナビゲーションの追加
   - タスクリストとボイスメモの統合

2. **`pubspec.yaml`**
   - 必要なパッケージの追加

3. **`android/app/src/main/AndroidManifest.xml`**
   - Android権限の追加
   - バックグラウンドサービスの設定

## 使用パッケージ

```yaml
dependencies:
  # 音声録音
  record: ^5.1.2
  
  # 加速度センサー
  sensors_plus: ^6.0.1
  
  # バックグラウンド実行
  flutter_background_service: ^5.0.10
  
  # ファイルパス取得
  path_provider: ^2.1.4
  
  # 音声再生
  audioplayers: ^6.1.0
  
  # 既存パッケージ
  speech_to_text: ^7.0.0
  shared_preferences: ^2.5.3
  permission_handler: ^12.0.0
```

## Android権限設定

```xml
<!-- 音声録音 -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- バックグラウンド実行 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />

<!-- ファイルアクセス -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

## 主要クラスの説明

### VoiceMemoService
```dart
class VoiceMemoService {
  // 振動検知の開始/停止
  Future<void> startShakeDetection();
  Future<void> stopShakeDetection();
  
  // 録音の開始/停止
  Future<void> startRecording();
  Future<void> stopRecording();
  
  // ボイスメモ管理
  Future<List<VoiceMemo>> getVoiceMemos();
  Future<void> deleteVoiceMemo(VoiceMemo voiceMemo);
}
```

### VoiceMemo
```dart
class VoiceMemo {
  String id;           // 一意識別子
  String filePath;     // 音声ファイルパス
  String title;        // 表示タイトル
  DateTime createdAt;  // 作成日時
  Duration duration;   // 録音時間
}
```

## 使用方法

### 1. 振動検知の開始
1. ボイスメモタブを開く
2. 「振動検知開始」ボタンをタップ
3. バックグラウンドサービスが開始される

### 2. 録音の実行
**方法1: 振動による録音**
- 端末を振る → 録音開始
- 再度端末を振る → 録音停止

**方法2: 手動録音**
- 「手動録音」ボタンをタップ → 録音開始
- 「録音停止」ボタンをタップ → 録音停止

### 3. ボイスメモの再生
1. 一覧からボイスメモをタップ
2. 再生/一時停止の切り替え
3. スライダーで再生位置の調整

### 4. ボイスメモの削除
- 削除ボタンをタップ、または
- ボイスメモを長押し

## 技術的特徴

### 振動検知アルゴリズム
```dart
// 3軸加速度の合成値を計算
final acceleration = sqrt(x² + y² + z²);

// 閾値を超えた場合に振動として検知
if (acceleration > 15.0) {
  onShakeDetected();
}
```

### バックグラウンド処理
- Androidのフォアグラウンドサービスを使用
- 通知領域に常駐して状態を表示
- アプリ終了後も振動検知を継続

### ファイル管理
- アプリ専用ディレクトリに保存
- 自動的なファイル名生成
- メタデータの永続化（SharedPreferences）

## プラットフォーム対応

### Android
- 完全対応
- バックグラウンド実行可能
- 全機能利用可能

### iOS
- 基本機能対応
- バックグラウンド制限あり
- App Store審査要件に注意

### Web
- 制限された機能のみ
- 振動検知・バックグラウンド実行不可
- 代替UI表示

## 今後の拡張可能性

1. **音声認識連携**: 録音内容の自動テキスト化
2. **クラウド同期**: 複数デバイス間でのボイスメモ共有
3. **音声品質向上**: ノイズキャンセリング機能
4. **カテゴリ分類**: ボイスメモのタグ付け・分類
5. **音声コマンド**: 音声による操作制御
6. **位置情報連携**: 録音場所の記録
7. **共有機能**: SNSやメッセージアプリへの共有

## セキュリティ考慮事項

1. **権限管理**: 必要最小限の権限要求
2. **ファイル暗号化**: 機密性の高い録音の保護
3. **アクセス制御**: アプリ内認証機能
4. **データ削除**: 完全なファイル削除機能
5. **プライバシー**: 録音データの外部送信制限