# 講義録（全自動講義録アプリ）

講義を録音しながら、リアルタイムで文字起こしするスマホアプリです（iPhone / Android）。

いまできること（Step 1）:

- 録音ボタンを押すと、話した内容がその場で画面に文字で流れる
- 講義ごとに文字起こし（`transcript.txt`）と録音（`audio.wav`）をスマホ内に保存
- 保存した講義の一覧・全文表示・全文コピー・削除
- 録音を終えると、Google の Gemini（無料枠、`gemini-flash-latest`、回数切れ時は `gemini-3.5-flash-lite`）が講義ノート形式の要約を自動で作る（`summary.txt` に保存）
- 予備の方法: 指示付きの文字起こしを Claude アプリに渡し、返ってきた要約を貼り付けて保存

これから: 検索や書き出し。

## Android で試す

1. Android スマホで次のリンクを開くと、アプリのファイル（`lecture-notes.apk`）がダウンロードされます
   https://github.com/siam0717glife-creator/lecture-notes/releases/latest/download/lecture-notes.apk
2. ダウンロードが終わったら通知（または「ファイル」アプリのダウンロード）から `lecture-notes.apk` をタップ
3. 「この提供元のアプリを許可」と出たら、設定で許可して戻り、「インストール」をタップ
4. [Deepgram](https://deepgram.com) に無料登録して API キーを作り、アプリ右上の設定に貼り付ける
5. [Google AI Studio](https://aistudio.google.com) の「Get API key」で Gemini の API キーを作り、同じ設定画面に貼り付ける（無料枠では送った内容が Google の改善に使われることがある）

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
| `lib/services/lecture_note_prompt.dart` | 要約の指示文（Gemini と Claude アプリで共通） |
| `lib/services/gemini_summarizer.dart` | Gemini API で要約（HTTP で直接呼び出し、ストリーミング受信） |

試作版のため、API キーはスマホ内に保存しています。他の人に配る前に中継サーバーへ移します。
