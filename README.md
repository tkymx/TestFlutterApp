# Flutter音声アプリ（Vosk Speech Recognition API対応版）

## 概要
音声認識機能を使用したFlutterアプリです。`speech_to_text` ライブラリを削除し、オープンソースのVosk Speech Recognition APIを直接使用するように修正されています。

## 主な機能

### 1. ボイスタスク（リアルタイム文字起こし）
- リアルタイムで音声をテキストに変換
- 連続音声認識機能
- 一時停止・再開機能
- タスクリストへの自動追加

### 2. ボイスメモ（音声ファイルからの文字起こし）
- 高品質な音声録音
- 録音後の音声ファイルからのテキスト変換
- 音声ファイルの再生機能
- メモの管理（作成・削除・一覧表示）

## 技術仕様

### Flutter側
- **Vosk Speech Recognition API**: MethodChannelを使用してネイティブAPI呼び出し
- **録音機能**: `record` パッケージ使用
- **音声再生**: `audioplayers` パッケージ使用
- **データ保存**: `shared_preferences` パッケージ使用

### Android側
- **Vosk Speech Recognizer**: オープンソース音声認識ライブラリ
- **RecognitionListener**: 音声認識イベントのハンドリング
- **MediaMetadataRetriever**: 音声ファイルのメタデータ読み取り

## 主な変更点

### 削除されたライブラリ
- `speech_to_text: ^7.0.0` （削除）

### 新しい実装
1. **MethodChannel**: `android_speech_recognition` チャンネル
2. **ネイティブKotlinコード**: `MainActivity.kt`でVosk音声認識処理
3. **統合音声サービス**: `UnifiedVoiceService`クラスの全面書き直し

### 機能の違い
| 機能 | 旧実装（speech_to_text） | 新実装（Vosk Speech Recognition API） |
|------|-------------------------|------------------------------------------|
| リアルタイム認識 | ✅ サポート | ✅ ネイティブサポート |
| 連続認識 | ✅ 制限あり | ✅ 改善された自動再起動 |
| 音声ファイル認識 | ❌ 非サポート | ✅ ネイティブサポート |
| 言語サポート | ✅ 多言語 | ✅ 日本語最適化 |
| エラーハンドリング | ⚠️ 基本的 | ✅ 詳細なエラー分類 |
| オフライン動作 | ❌ 要インターネット | ✅ 完全オフライン |

## セットアップ

### 必要な権限
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

### 依存関係のインストール
```bash
flutter pub get
```

### ビルドと実行
```bash
flutter run
```

## 使用方法

### ボイスタスク
1. 「タスクリスト」タブを選択
2. マイクボタンをタップして音声認識開始
3. 話した内容がリアルタイムでテキスト化
4. 「追加」ボタンでタスクリストに追加

### ボイスメモ
1. 「ボイスメモ」タブを選択
2. 録音ボタンをタップして録音開始
3. 録音停止後、自動的にテキスト変換
4. 音声ファイルとテキストが保存される

## 注意事項

### 音声ファイルからの文字起こし
Vosk Speech Recognition APIを使用して、録音された音声ファイルから直接文字起こしを実行します。オフラインで動作するため、インターネット接続は不要です。

### Voskモデルについて
- 日本語小モデル（vosk-model-small-ja-0.22）を使用
- 約30MBのコンパクトなモデル
- オフライン音声認識に対応
- 初回起動時に自動ダウンロード

### プラットフォーム対応
- **Android**: 完全対応（Vosk APIネイティブサポート）
- **iOS**: 未対応（iOS Vosk Framework要実装）
- **Web**: 制限あり（Web Speech API使用可能）

## 開発者向け情報

### MethodChannelメソッド
- `initialize`: Vosk音声認識の初期化
- `startListening`: Vosk音声認識開始
- `stopListening`: Vosk音声認識停止
- `transcribeAudioFile`: Vosk音声ファイル文字起こし（フルサポート）
- `cleanup`: リソースクリーンアップ

### コールバックメソッド
- `onPartialResult`: 部分的な認識結果
- `onFinalResult`: 最終的な認識結果
- `onError`: エラー通知
- `onListeningStarted`: 認識開始通知
- `onListeningStopped`: 認識停止通知

## 今後の改善案

1. **iOS対応**: iOS Vosk Framework実装
2. **モデル管理**: 他言語モデルの動的ダウンロード
3. **音声品質向上**: ノイズフィルタリング機能
4. **話者識別**: 複数話者対応（Vosk拡張）
5. **感情分析**: 音声からの感情認識
6. **大語彙モデル**: より精度の高い大モデル対応

## ライセンス
MITライセンス
