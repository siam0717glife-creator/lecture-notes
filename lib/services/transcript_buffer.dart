/// 文字起こし結果を「確定した文」と「認識中の文」に分けて持つ。
///
/// ストリーミング音声認識は、同じ区間について途中結果を何度も送り、
/// 最後に確定結果を1回送る。途中結果は毎回置き換え、確定結果だけを積み上げる。
class TranscriptBuffer {
  final List<String> _finals = [];
  String _interim = '';

  /// 確定した文の一覧（古い順）。
  List<String> get finals => List.unmodifiable(_finals);

  /// まだ確定していない、認識中の文。
  String get interim => _interim;

  /// 確定した文をすべてつないだ全文。
  String get finalText => _finals.join('\n');

  /// 認識中の文も含めた、画面表示用の全文。
  String get displayText => _interim.isEmpty
      ? finalText
      : [...?_nonEmpty(finalText), _interim].join('\n');

  void add(String text, {required bool isFinal}) {
    final cleaned = normalizeJapanese(text);
    if (isFinal) {
      if (cleaned.isNotEmpty) _finals.add(cleaned);
      _interim = '';
    } else {
      _interim = cleaned;
    }
  }

  /// 録音停止時など、認識中の文も確定扱いにする。
  void flushInterim() {
    if (_interim.isNotEmpty) _finals.add(_interim);
    _interim = '';
  }

  static List<String>? _nonEmpty(String s) => s.isEmpty ? null : [s];
}

final _cjk = RegExp(r'[　-ヿ㐀-鿿＀-￯]');

/// 音声認識が日本語の単語間に入れる空白を取り除く。
/// 英数字どうしの間の空白（例: "Hello world"）は残す。
String normalizeJapanese(String text) {
  final t = text.trim();
  final buf = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == ' ' && i > 0 && i < t.length - 1) {
      final prev = t[i - 1];
      final next = t[i + 1];
      if (_cjk.hasMatch(prev) || _cjk.hasMatch(next)) continue;
    }
    buf.write(c);
  }
  return buf.toString();
}
