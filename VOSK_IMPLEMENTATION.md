# Voskを使った日本語音声書き起こし実装

## 概要
ボイスメモモードで音声を収録した後に、Vosk Speech Recognition APIを使って日本語の書き起こしを実際に行う機能を実装しました。

## 実装内容

### 1. Androidネイティブコード (MainActivity.kt)

#### 新機能
- **performVoskTranscription()**: 実際のVosk音声認識処理
- **convertAudioToPcm()**: M4A/AACファイルをPCMデータに変換
- **resampleAudio()**: サンプリングレートを16kHzに変換

#### 主な処理フロー
1. 音声ファイル（M4A/AAC）をMediaExtractorで読み込み
2. MediaCodecでPCMデータにデコード
3. サンプリングレートを16kHzに変換（Voskの要求）
4. PCMデータをバイト配列に変換
5. VoskのRecognizerでチャンクごとに音声認識
6. 認識結果をJSONから抽出して返却

### 2. Dartコード (unified_voice_service.dart)

#### 更新内容
- **transcribeAudioFile()**: Vosk APIを使った書き起こし処理
- **_processVoiceMemoRecordedFile()**: Vosk書き起こし結果の処理
- ログメッセージとステータス表示をVosk対応に更新

### 3. UI更新 (voice_memo_page.dart)

#### 変更点
- 状態表示を「統合版」から「Vosk対応」に変更
- 書き起こし完了メッセージにVosk表記を追加

## 技術仕様

### Voskモデル
- **モデル**: vosk-model-small-ja-0.22
- **言語**: 日本語
- **サンプリングレート**: 16kHz
- **配置場所**: `android/app/src/main/assets/vosk-model-small-ja-0.22/`

### 音声処理
- **入力形式**: M4A/AAC (44.1kHz)
- **変換形式**: PCM 16bit (16kHz)
- **チャンクサイズ**: 8000バイト (0.25秒分)

### 依存関係
- **Vosk Android**: 0.3.32
- **JNA**: 5.13.0
- **MediaCodec**: Android標準API

## 使用方法

1. ボイスメモ録音ボタンを押して録音開始
2. 音声を録音
3. 録音停止ボタンを押す
4. 自動的にVoskで書き起こし処理が開始
5. 書き起こし結果がボイスメモのタイトルと内容に反映

## エラーハンドリング

- Voskモデルファイルが見つからない場合: 録音のみ実行
- 音声ファイルが短すぎる場合: エラーメッセージ表示
- PCM変換失敗: 書き起こしなしで保存
- 音声認識失敗: 書き起こしなしで保存

## パフォーマンス

- 音声ファイルサイズに応じて処理時間が変動
- 1分の録音で約5-10秒の書き起こし時間（デバイス性能による）
- メモリ使用量: 音声ファイルサイズの約3-4倍

## 今後の改善点

1. **リアルタイム書き起こし**: 録音中の同時書き起こし
2. **精度向上**: より大きなVoskモデルの使用
3. **バックグラウンド処理**: 書き起こし中の他操作許可
4. **進捗表示**: 書き起こし進捗のリアルタイム表示