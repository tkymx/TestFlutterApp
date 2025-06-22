# Vosk日本語小モデル配置指示

## モデルのダウンロードと配置

1. 以下のURLから日本語小モデルをダウンロードしてください：
   https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip

2. ダウンロードしたZIPファイルを解凍し、中身の全てのファイルを
   このフォルダ（/android/app/src/main/assets/vosk-model-small-ja-0.22/）に配置してください。

## 必要なファイル
- am/final.mdl
- ivector/final.dubm
- ivector/final.ie
- ivector/global_cmvn.stats
- ivector/online_cmvn.conf
- ivector/splice.conf
- conf/model.conf
- conf/mfcc.conf
- graph/HCLG.fst
- graph/words.txt
- graph/phones/
- その他のファイル

## 注意事項
- モデルファイルのサイズが大きいため、gitに含めていません
- 実際のアプリケーションでは、初回起動時にモデルを自動ダウンロードする
  機能を実装することを推奨します
