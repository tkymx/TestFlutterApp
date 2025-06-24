# ボイスタスク追加機能の実装

## 概要
従来の複雑な音声入力UIを削除し、シンプルで直感的なボイスタスク追加機能を実装しました。

## 主な変更点

### 1. 既存機能の削除
- `TaskListPage`の音声入力エリア（テキストフィールド、音声入力ボタン、追加ボタン）を完全削除
- 複雑なMethodChannelの直接操作を削除
- 古い音声認識の初期化コードを削除

### 2. 新しいUI実装

#### 右下の録音ボタン
```dart
floatingActionButton: !kIsWeb && !_showDraftCard && _isInitialized
    ? FloatingActionButton(
        onPressed: _startVoiceRecording,
        backgroundColor: _voiceService.speechEnabled ? Colors.blue : Colors.grey,
        child: const Icon(Icons.mic, color: Colors.white),
      )
    : null,
```

#### ドラフトタスクカード
- 音声認識中の状態表示（マイクアイコン + プログレスインジケーター）
- リアルタイム音声認識結果の表示エリア
- 「キャンセル」と「タスク追加」ボタン

### 3. 音声サービスの統合
既存の`UnifiedVoiceService`を活用：

```dart
final UnifiedVoiceService _voiceService = UnifiedVoiceService();

// コールバック設定
_voiceService.onTranscriptionUpdated = (text) {
  setState(() {
    _draftTaskContent = text;
  });
};
```

### 4. 新しいワークフロー

1. **録音開始**: 右下の録音ボタンを押す
2. **ドラフト表示**: ドラフトタスクカードが表示される
3. **音声認識**: リアルタイムで音声が文字に変換される
4. **確認・追加**: 内容を確認して「タスク追加」または「キャンセル」

## 実装詳細

### 状態管理
```dart
bool _isInitialized = false;
bool _isRecording = false;
String _draftTaskContent = '';
bool _showDraftCard = false;
```

### 主要メソッド

#### 音声録音開始
```dart
void _startVoiceRecording() async {
  if (kIsWeb || !_voiceService.speechEnabled) {
    // エラーハンドリング
    return;
  }
  
  setState(() {
    _showDraftCard = true;
    _draftTaskContent = '';
  });
  
  await _voiceService.startContinuousListening();
}
```

#### ドラフトタスク追加
```dart
void _addDraftTask() {
  if (_draftTaskContent.trim().isEmpty) return;
  
  final newTask = Task(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    content: _draftTaskContent.trim(),
    createdAt: DateTime.now(),
  );
  
  setState(() {
    _tasks.insert(0, newTask);
    _showDraftCard = false;
    _draftTaskContent = '';
  });
  
  _stopVoiceRecording();
  _saveTasks();
}
```

#### ドラフトキャンセル
```dart
void _cancelDraftTask() {
  setState(() {
    _showDraftCard = false;
    _draftTaskContent = '';
  });
  _stopVoiceRecording();
}
```

## UI改善

### ドラフトカードのデザイン
- オレンジ色の背景で目立つデザイン
- 音声認識状態の視覚的フィードバック
- 認識結果の白い背景エリア
- 分かりやすいボタン配置

### エラーハンドリング
- Web環境での適切な通知
- 音声認識機能が無効な場合の通知
- 録音ボタンの色による状態表示

### アクセシビリティ
- 明確な視覚的フィードバック
- 分かりやすいボタンラベル
- 適切なアイコンの使用

## 技術的メリット

1. **コードの簡素化**: 複雑なMethodChannel操作を削除
2. **保守性向上**: 既存のUnifiedVoiceServiceを活用
3. **ユーザビリティ**: 直感的で分かりやすい操作
4. **エラー処理**: 適切なエラーハンドリングと通知

## ファイル変更

### 主要変更ファイル
- `lib/main.dart`: TaskListPageの完全リファクタリング

### 追加ファイル
- `voice_task_demo.html`: 機能デモページ
- `VOICE_TASK_IMPLEMENTATION.md`: この実装ドキュメント

## 今後の拡張可能性

1. **音声コマンド**: 「追加」「キャンセル」の音声コマンド対応
2. **編集機能**: ドラフトカードでのテキスト編集機能
3. **音声フィードバック**: 操作完了時の音声通知
4. **複数言語対応**: 多言語での音声認識対応

## 使用方法

1. アプリを起動
2. 右下の青い録音ボタンをタップ
3. ドラフトカードが表示されたら音声でタスク内容を話す
4. 認識結果を確認して「タスク追加」または「キャンセル」を選択

この実装により、ユーザーはより簡単で直感的にボイスタスクを追加できるようになりました。