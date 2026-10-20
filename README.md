# 講義録（全自動講義録アプリ）

講義を録音しながら、リアルタイムで文字起こしするスマホアプリです（iPhone / Android）。

いまできること（Step 1）:

- 録音ボタンを押すと、話した内容がその場で画面に文字で流れる
- 講義ごとに文字起こし（`transcript.txt`）と録音（`audio.wav`）をスマホ内に保存
- 保存した講義の一覧・全文表示・全文コピー・削除
- 録音を終えると、Claude（claude-haiku-5-5、1回約1円）が講義ノート形式の要約を自動で作る（`summary.txt` に保存、作り直しも可）
- API キー無しでも「Claudeアプリで要約する（無料）」で、指示付きの文字起こしを Claude アプリに渡せる

これから: 中継サーバー（APIキーをアプリから外す）、検索や書き出し。

## Android で試す

1. Android スマホで次のリンクを開くと、アプリのファイル（`lecture-notes.apk`）がダウンロードされます
   https://github.com/siam0717glife-creator/lecture-notes/releases/latest/download/lecture-notes.apk
2. ダウンロードが終わったら通知（または「ファイル」アプリのダウンロード）から `lecture-notes.apk` をタップ
3. 「この提供元のアプリを許可」と出たら、設定で許可して戻り、「インストール」をタップ
4. [Deepgram](https://deepgram.com) に無料登録して API キーを作り、アプリ右上の設定に貼り付ける
5. 要約を使うときは [Anthropic Console](https://console.anthropic.com) で API キーを作り、同じ設定画面の「Claude API キー」に貼り付ける

## iPhone で試す

iPhone 向けのビルドには Mac が必要です。Mac が無い場合は Codemagic などのクラウドビルドを使い、
Apple Developer Program（有料）に登録したうえで TestFlight で配布します（準備中）。

## 開発者向け

- Flutter 3.47.7
- 文字起こし: Deepgram のストリーミング音声認識（`lib/services/deepgram_transcriber.dart`、16kHz モノラル PCM を WebSocket で送信）
- `flutter test` でテスト、`flutter analyze` で静的解析

| ファイル | 役割 |
|---|---|
| `lib/main.dart` | 講義の一覧画面 |
| `lib/screens/recording_screen.dart` | 録音・リアルタイム文字起こし画面 |
| `lib/screens/settings_screen.dart` | API キーの設定画面 |
| `lib/screens/lecture_detail_screen.dart` | 保存した講義の全文表示 |
| `lib/services/transcript_buffer.dart` | 途中結果と確定結果の管理、日本語の空白除去 |
| `lib/services/wav_writer.dart` | 録音を WAV ファイルに保存 |
| `lib/services/lecture_store.dart` | 講義の保存・一覧・削除 |
| `lib/services/claude_summarizer.dart` | Claude API で要約（HTTP で直接呼び出し、ストリーミング受信） |

試作版のため、API キーはスマホ内に保存しています。他の人に配る前に中継サーバーへ移します。
