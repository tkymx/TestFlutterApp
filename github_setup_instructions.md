# GitHub リポジトリセットアップ手順

このFlutterプロジェクトをGitHubにプッシュするための手順です。

## 1. GitHubでリポジトリを作成

1. [GitHub](https://github.com) にログインします
2. 右上の「+」ボタンをクリックし、「New repository」を選択します
3. 以下の情報を入力します：
   - Repository name: `flutter-app-deploygate` (または任意の名前)
   - Description: `Flutter app with GitHub Actions CI/CD and DeployGate integration`
   - Visibility: Public または Private
   - 「Initialize this repository with a README」のチェックを外す
4. 「Create repository」ボタンをクリックします

## 2. ローカルリポジトリをGitHubにプッシュ

GitHubリポジトリを作成したら、以下のコマンドを実行してプロジェクトをプッシュします：

```bash
# 現在のディレクトリがflutter_appであることを確認
cd /workspace/flutter_app

# リモートリポジトリを追加（URLは作成したリポジトリのものに置き換えてください）
git remote add origin https://github.com/ユーザー名/flutter-app-deploygate.git

# mainブランチをプッシュ
git push -u origin main
```

## 3. GitHub Actionsの設定

GitHub Actionsを使用してDeployGateにデプロイするには、以下のシークレットを設定する必要があります：

1. GitHubリポジトリのページで「Settings」タブをクリックします
2. 左側のメニューから「Secrets and variables」→「Actions」を選択します
3. 「New repository secret」ボタンをクリックして以下のシークレットを追加します：
   - `DEPLOYGATE_API_TOKEN`: DeployGateのAPIトークン
   - `DEPLOYGATE_USER_NAME`: DeployGateのユーザー名

## 4. DeployGateのセットアップ

1. [DeployGate](https://deploygate.com/) にサインアップまたはログインします
2. アカウント設定からAPIトークンを取得します
3. 上記の手順でGitHubリポジトリのシークレットとして設定します

## 5. GitHub Actionsの実行

リポジトリにプッシュすると、GitHub Actionsが自動的に実行されます。ワークフローの進行状況は、GitHubリポジトリの「Actions」タブで確認できます。

## 注意事項

- GitHub Actionsのワークフローは、mainブランチとdevelopブランチへのプッシュ時に実行されます
- DeployGateへのデプロイは、mainブランチとdevelopブランチへのプッシュ時のみ行われます
- プルリクエストが作成された場合は、ビルドとテストのみが実行されます