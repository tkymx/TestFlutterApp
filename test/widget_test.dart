// 音声タスクリストアプリのウィジェットテスト
//
// このテストファイルは、タスクリストアプリの基本機能をテストします。

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

      // 初期状態では「タスクがありません」メッセージが表示されることを確認
      expect(find.textContaining('タスクがありません'), findsOneWidget);

      // テキスト入力フィールドが存在することを確認
      expect(find.byType(TextField), findsOneWidget);

      // 追加ボタンが存在することを確認
      expect(find.text('追加'), findsOneWidget);
    });

    testWidgets('テキスト入力によるタスク追加テスト', (WidgetTester tester) async {
      // アプリを起動
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // テキストフィールドにタスクを入力
      const testTask = 'テストタスク';
      await tester.enterText(find.byType(TextField), testTask);
      await tester.pump();

      // 追加ボタンをタップ
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      // タスクが追加されたことを確認
      expect(find.text(testTask), findsOneWidget);

      // 「タスクがありません」メッセージが消えたことを確認
      expect(find.textContaining('タスクがありません'), findsNothing);

      // チェックボックスが表示されることを確認
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('空のタスクは追加されないテスト', (WidgetTester tester) async {
      // アプリを起動
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 空のテキストで追加ボタンをタップ
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      // 「タスクがありません」メッセージが残っていることを確認
      expect(find.textContaining('タスクがありません'), findsOneWidget);

      // チェックボックスが表示されないことを確認
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
