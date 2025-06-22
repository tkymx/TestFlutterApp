# Android HWC (Hardware Composer) エラー対処法

## エラーの概要
```
resetColorMappingInfoForClientComp:: resetColorMappingInfo() idx=0/1/2 error(-22)
```

このエラーはAndroid Hardware Composer (HWC) のカラーマッピング処理で発生する問題です。

## 原因
1. **ハードウェア固有の問題**: 特定のAndroidデバイスのGPU/ディスプレイドライバーとの互換性
2. **権限不足**: システムレベルのログディレクトリへの書き込み権限がない
3. **Android APIレベルの互換性**: Flutter SDKとAndroidバージョンの不整合

## 実装済み対処法

### 1. AndroidManifest.xml の設定
- `android:enableOnBackInvokedCallback="true"` を追加
- ハードウェアアクセラレーションの最適化

### 2. build.gradle の最適化
- NDK ABIフィルターの設定
- ProGuard設定によるリリースビルド最適化
- デバッグビルドでの最適化無効化

### 3. MainActivity.kt の改良
- ハードウェアアクセラレーション設定の例外処理
- エラーログの適切な出力

### 4. ProGuard設定
- ハードウェア関連クラスの保護
- Flutter関連クラスの保護
- 音声認識・センサー関連クラスの保護

## 追加の対処法

### デバイス固有の対処
1. **開発者オプションでの設定**
   - GPU レンダリングを強制的に有効化
   - ハードウェアオーバーレイを無効化

2. **アプリレベルでの対処**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --debug
   ```

3. **特定デバイスでの回避策**
   - Samsung Galaxy: 開発者オプション > GPU デバッグレイヤーを無効化
   - Xiaomi: MIUI最適化を無効化
   - Huawei: GPU Turboを無効化

### ログ確認方法
```bash
# HWCエラーの詳細確認
adb logcat | grep -i hwc

# Flutter関連ログの確認
adb logcat | grep -i flutter

# システムレベルのエラー確認
adb logcat | grep -E "(ERROR|FATAL)"
```

## 影響度評価
- **機能への影響**: 通常は表示に関する警告レベル
- **パフォーマンス**: 軽微な影響（一部デバイスで描画性能低下の可能性）
- **安定性**: アプリクラッシュの原因にはならない

## 推奨事項
1. エラーが発生してもアプリが正常動作する場合は、警告として扱う
2. 特定デバイスで表示問題が発生する場合のみ、デバイス固有の対処を実施
3. リリース前に複数デバイスでのテストを実施

## 関連リンク
- [Android Hardware Composer Documentation](https://source.android.com/devices/graphics/hwc)
- [Flutter Android Build Configuration](https://docs.flutter.dev/deployment/android)
- [Android Graphics Architecture](https://source.android.com/devices/graphics/architecture)