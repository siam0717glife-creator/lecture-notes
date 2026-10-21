/// 文字起こしの「話者1：」などを、あとから人の名前に置き換える。
///
/// 文字起こし本体は書き換えず、名前の対応だけを別に保存しておく。
/// こうすると、何度でも名前を付け直せる。
class SpeakerNames {
  static final _label = RegExp(r'^(話者\d+)：', multiLine: true);

  /// 文字起こしに出てくる話者を、出てきた順に返す（例: [話者1, 話者2]）。
  static List<String> find(String transcript) =>
      _label.allMatches(transcript).map((m) => m.group(1)!).toSet().toList();

  /// 名前が付いている話者を、その名前に置き換えた文章を返す。
  static String apply(String transcript, Map<String, String> names) =>
      transcript.replaceAllMapped(_label, (m) {
        final name = names[m.group(1)]?.trim() ?? '';
        return '${name.isEmpty ? m.group(1) : name}：';
      });
}
