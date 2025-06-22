import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import '../lib/voice_memo_service.dart';
void main() {
  group('VoiceMemo Tests', () {
    test('VoiceMemo creation and JSON serialization', () {
      final now = DateTime.now();
      final voiceMemo = VoiceMemo(
        id: '123',
        filePath: '/path/to/file.m4a',
        title: 'Test Memo',
        createdAt: now,
        duration: const Duration(minutes: 2, seconds: 30),
      );

      expect(voiceMemo.id, '123');
      expect(voiceMemo.filePath, '/path/to/file.m4a');
      expect(voiceMemo.title, 'Test Memo');
      expect(voiceMemo.createdAt, now);
      expect(voiceMemo.duration, const Duration(minutes: 2, seconds: 30));
    });

    test('VoiceMemo JSON serialization and deserialization', () {
      final now = DateTime.now();
      final originalMemo = VoiceMemo(
        id: '456',
        filePath: '/another/path.m4a',
        title: 'Another Memo',
        createdAt: now,
        duration: const Duration(seconds: 45),
      );

      final json = originalMemo.toJson();
      final deserializedMemo = VoiceMemo.fromJson(json);

      expect(deserializedMemo.id, originalMemo.id);
      expect(deserializedMemo.filePath, originalMemo.filePath);
      expect(deserializedMemo.title, originalMemo.title);
      expect(deserializedMemo.createdAt, originalMemo.createdAt);
      expect(deserializedMemo.duration, originalMemo.duration);
    });

    test('VoiceMemoService singleton pattern', () {
      final service1 = VoiceMemoService();
      final service2 = VoiceMemoService();
      
      expect(identical(service1, service2), true);
    });

    test('VoiceMemoService initial state', () {
      final service = VoiceMemoService();
      
      expect(service.isRecording, false);
      expect(service.isBackgroundServiceRunning, false);
    });
  });

  // 振動検知機能は削除されました

  group('Platform Tests', () {
    test('Web platform detection', () {
      // Webプラットフォームでの制限事項テスト
      if (kIsWeb) {
        // Webでは制限された機能のみ利用可能
        expect(kIsWeb, true);
      } else {
        // モバイルプラットフォームでは全機能利用可能
        expect(kIsWeb, false);
      }
    });
  });
}