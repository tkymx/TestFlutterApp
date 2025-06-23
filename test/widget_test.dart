// 音声タスクリストアプリのウィジェットテスト
//
// このテストファイルは、新しいボイスタスク追加機能をテストします。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('音声タスクリストアプリのテスト', () {
    testWidgets('アプリの初期状態テスト', (WidgetTester tester) async {
      // アプリを起動
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // タブが表示されることを確認
      expect(find.text('タスクリスト'), findsOneWidget);
      expect(find.text('ボイスメモ'), findsOneWidget);

      // アプリバーのタイトルが表示されることを確認
      expect(find.text('音声タスクリスト'), findsOneWidget);

      // 初期状態では「タスクがありません」メッセージが表示されることを確認
      expect(find.textContaining('タスクがありません'), findsOneWidget);

      // 古いテキスト入力フィールドが存在しないことを確認
      expect(find.byType(TextField), findsNothing);

      // 古い追加ボタンが存在しないことを確認
      expect(find.text('追加'), findsNothing);
    });

    testWidgets('UI構造テスト', (WidgetTester tester) async {
      // アプリを起動
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 基本的なUI要素が存在することを確認
      expect(find.text('音声タスクリスト'), findsOneWidget);
      
      // ドラフトカードが初期状態では表示されないことを確認
      expect(find.text('音声認識中...'), findsNothing);
      expect(find.text('キャンセル'), findsNothing);
      expect(find.text('タスク追加'), findsNothing);
    });

    testWidgets('タスクリスト表示テスト', (WidgetTester tester) async {
      // アプリを起動
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 空のメッセージが表示されることを確認
      expect(find.textContaining('タスクがありません'), findsOneWidget);
      
      // 環境に応じたメッセージが表示されることを確認（Web環境かモバイル環境か）
      final hasWebMessage = find.textContaining('Webでは音声機能は利用できません').evaluate().isNotEmpty;
      final hasMobileMessage = find.textContaining('右下の録音ボタンでタスクを追加してください').evaluate().isNotEmpty;
      
      // どちらかのメッセージが表示されていることを確認
      expect(hasWebMessage || hasMobileMessage, isTrue);
    });

    testWidgets('タスクリスト基本機能テスト', (WidgetTester tester) async {
      // アプリを起動
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 初期状態では「タスクがありません」メッセージが表示されることを確認
      expect(find.textContaining('タスクがありません'), findsOneWidget);

      // チェックボックスが表示されないことを確認（タスクがないため）
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
