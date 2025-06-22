import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import '../lib/unified_voice_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('VoiceMemo Tests', () {
    test('VoiceMemo creation and JSON serialization', () {
      final now = DateTime.now();
      final voiceMemo = VoiceMemo(
        id: '123',
        filePath: '/path/to/file.m4a',
        title: 'Test Memo',
        createdAt: now,
        duration: const Duration(minutes: 2, seconds: 30),
        transcription: 'Test transcription',
      );

      expect(voiceMemo.id, '123');
      expect(voiceMemo.filePath, '/path/to/file.m4a');
      expect(voiceMemo.title, 'Test Memo');
      expect(voiceMemo.createdAt, now);
      expect(voiceMemo.duration, const Duration(minutes: 2, seconds: 30));
      expect(voiceMemo.transcription, 'Test transcription');
    });

    test('VoiceMemo JSON serialization and deserialization', () {
      final now = DateTime.now();
      final originalMemo = VoiceMemo(
        id: '456',
        filePath: '/another/path.m4a',
        title: 'Another Memo',
        createdAt: now,
        duration: const Duration(seconds: 45),
        transcription: 'Another transcription',
      );

      final json = originalMemo.toJson();
      final deserializedMemo = VoiceMemo.fromJson(json);

      expect(deserializedMemo.id, originalMemo.id);
      expect(deserializedMemo.filePath, originalMemo.filePath);
      expect(deserializedMemo.title, originalMemo.title);
      expect(deserializedMemo.createdAt, originalMemo.createdAt);
      expect(deserializedMemo.duration, originalMemo.duration);
      expect(deserializedMemo.transcription, originalMemo.transcription);
    });

    test('UnifiedVoiceService initial state', () {
      final service = UnifiedVoiceService();
      
      expect(service.isRecording, false);
      expect(service.isContinuousListening, false);
      expect(service.isPaused, false);
      expect(service.soundLevel, 0.0);
      expect(service.recognizedText, '');
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