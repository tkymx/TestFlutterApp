# 音声タスクリスト - Flutter Android アプリ

音声入力とテキスト入力の両方に対応したタスク管理アプリです。

## 機能

### 🎤 音声入力機能
- **タップして音声入力**: 音声入力ボタンをタップして音声でタスクを追加
- **日本語音声認識**: 日本語に最適化された音声認識
- **リアルタイム認識**: 音声認識中の視覚的フィードバック
- **自動権限管理**: マイクの権限を自動的にリクエスト

### 📝 タスク管理機能
- **タスクの追加**: テキスト入力または音声入力でタスクを追加
- **完了状態の切り替え**: チェックボックスでタスクの完了/未完了を管理
- **タスクの削除**: 不要なタスクを削除
- **作成日時表示**: 各タスクの作成日時を表示
- **データ永続化**: アプリを再起動してもタスクが保持される

### 🎨 ユーザーインターフェース
- **直感的なデザイン**: Material Design 3を採用
- **レスポンシブレイアウト**: 様々な画面サイズに対応
- **視覚的フィードバック**: 音声認識中のアニメーション表示
- **カラーコード**: 機能別に色分けされたボタン

### 🌐 プラットフォーム対応
- **Android**: 完全な音声入力機能
- **Web**: テキスト入力のみ（音声入力は制限）
- **クロスプラットフォーム**: 同一コードベースで複数プラットフォーム対応

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
