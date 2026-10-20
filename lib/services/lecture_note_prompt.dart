/// 講義ノート形式の要約を作ってもらうための指示文。
///
/// Gemini（無料枠）での自動要約と、Claude アプリに手で渡す方法の両方で使う。
class LectureNotePrompt {
  static const instructions = '''
あなたは大学の講義ノートを作る優秀なアシスタントです。
下にあるのは講義を音声認識で文字起こししたテキストです。聞き間違いや言い直しが含まれるので、文脈から正しい内容を推測して整理してください。
学生があとで復習や試験勉強に使うことを想定し、日本語で次の形式の講義ノートを書いてください。

【この講義のまとめ】
3〜5文で、講義全体の内容を説明する。

【要点】
・重要なポイントを、講義で話された順に箇条書きにする（5〜10個程度）。

【キーワード】
・用語：意味を一言で（講義に出てきた専門用語や重要な語）

【試験に出そうなところ】
・講師が強調した点や「大事」「試験に出る」と言った点。無ければ重要そうな点を挙げる。

ルール:
・見出しは【】、箇条書きは「・」を使う。Markdown の記号（#、*、**）は使わない。
・文字起こしに無い内容を作り足さない。不明な部分は「（聞き取り不明）」と書く。
''';

  /// 講義名と文字起こしを入れた依頼文。
  static String userMessage(String title, String transcript) =>
      '講義名: $title\n\n<transcript>\n$transcript\n</transcript>\n\n'
      'この講義の講義ノートを作ってください。';

  /// 指示と依頼文をまとめた、Claude アプリなどに貼り付ける用の文章。
  static String build({required String title, required String transcript}) =>
      '$instructions\n${userMessage(title, transcript)}';
}
