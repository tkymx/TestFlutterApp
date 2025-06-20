# Flutter App

A Flutter application with automated Android build and deployment to DeployGate.

## Features

- Flutter 3.24.5 with Android support
- GitHub Actions CI/CD pipeline
- Automated deployment to DeployGate
- APK and App Bundle generation

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
