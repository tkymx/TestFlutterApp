# 音声アプリ - ボイスメモ & タスクリスト

端末を振ることでボイスメモの録音を開始/停止できる革新的な音声アプリです。バックグラウンドでも動作し、音声認識によるタスク管理機能も搭載しています。

## 🎯 主要機能

### 🎙️ ボイスメモ機能
- **振動検知録音**: 端末を振るだけで録音開始/停止
- **バックグラウンド動作**: アプリを閉じても振動検知が継続
- **高品質録音**: AAC-LC形式（44.1kHz、128kbps）
- **自動ファイル管理**: 日時ベースの自動命名・保存
- **再生機能**: ワンタップで再生/一時停止
- **メタデータ表示**: 録音日時・長さの表示

### 📝 タスクリスト機能
- **音声入力**: 音声認識によるタスク追加
- **テキスト入力**: 手動でのタスク入力も可能
- **完了管理**: チェックボックスでタスク完了管理
- **データ永続化**: アプリ再起動後もデータ保持

### 🎨 ユーザーインターフェース
- **タブナビゲーション**: タスクリストとボイスメモの切り替え
- **直感的なデザイン**: Material Design 3を採用
- **視覚的フィードバック**: 録音状態・音声認識中の表示
- **レスポンシブレイアウト**: 様々な画面サイズに対応

### 🌐 プラットフォーム対応
- **Android**: 全機能対応（振動検知・バックグラウンド実行）
- **iOS**: 基本機能対応（バックグラウンド制限あり）
- **Web**: 制限された機能のみ（タスクリスト中心）

## Getting Started

### Prerequisites

- Flutter SDK 3.24.5 or later
- Android SDK
- Java 17

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd flutter_app
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## CI/CD Pipeline

This project uses GitHub Actions for continuous integration and deployment:

- **Build**: Automatically builds APK and App Bundle on push to main/develop branches
- **Test**: Runs Flutter tests
- **Deploy**: Uploads APK to DeployGate for main and develop branches

### Setup DeployGate Integration

To enable DeployGate deployment, add the following secrets to your GitHub repository:

1. Go to your repository Settings > Secrets and variables > Actions
2. Add the following secrets:
   - `DEPLOYGATE_API_TOKEN`: Your DeployGate API token
   - `DEPLOYGATE_USER_NAME`: Your DeployGate username

### Getting DeployGate Credentials

1. Sign up at [DeployGate](https://deploygate.com/)
2. Go to Account Settings > API key to get your API token
3. Your username is displayed in your profile

## Project Structure

```
flutter_app/
├── android/          # Android-specific code
├── lib/              # Dart source code
│   └── main.dart     # Main application entry point
├── test/             # Test files
├── .github/
│   └── workflows/    # GitHub Actions workflows
└── pubspec.yaml      # Project dependencies
```

## Development

### Running Tests

```bash
flutter test
```

### Building for Release

```bash
# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle --release
```

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [DeployGate Documentation](https://docs.deploygate.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
