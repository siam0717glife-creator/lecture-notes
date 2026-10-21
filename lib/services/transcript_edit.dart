/// 文字起こしの1行を、あとから手で直す。
class TranscriptEdit {
  static final _label = RegExp(r'^(話者\d+)：');

  /// [line] の頭の「話者1：」を除いた、本文だけを返す。
  static String body(String line) => line.replaceFirst(_label, '');

  /// [index] 行目の本文を [newText] にする。話者の名前はそのまま残す。
  ///
  /// [newText] が空なら、その行を消す。消した行に話者名が付いていて、
  /// 次の行に名前が無ければ、次の行に名前を引き継ぐ。
  /// [starts]（各行の時刻）も、行と同じように更新して返す。
  static ({String transcript, List<double?>? starts}) editLine(
    String transcript,
    List<double?>? starts,
    int index,
    String newText,
  ) {
    final lines = transcript.split('\n');
    final aligned = starts != null && starts.length == lines.length;
    final newStarts = aligned ? [...starts] : starts;
    final label = _label.firstMatch(lines[index])?.group(0) ?? '';
    final text = newText.replaceAll('\n', ' ').trim();
    if (text.isNotEmpty) {
      lines[index] = '$label$text';
    } else {
      lines.removeAt(index);
      if (aligned) newStarts!.removeAt(index);
      if (label.isNotEmpty &&
          index < lines.length &&
          !_label.hasMatch(lines[index])) {
        lines[index] = '$label${lines[index]}';
      }
    }
    return (transcript: lines.join('\n'), starts: newStarts);
  }
}
