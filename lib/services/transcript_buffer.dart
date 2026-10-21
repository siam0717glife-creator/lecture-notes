/// 文字起こし結果を「確定した文」と「認識中の文」に分けて持つ。
///
/// ストリーミング音声認識は、同じ区間について途中結果を何度も送り、
/// 最後に確定結果を1回送る。途中結果は毎回置き換え、確定結果だけを積み上げる。
///
/// 話者がわかるときは、話す人が変わった文の頭に「話者1：」のように付ける。
class TranscriptBuffer {
  final List<String> _finals = [];
  final List<double?> _starts = [];
  String _interim = '';
  int? _interimSpeaker;
  double? _interimStart;
  int? _lastSpeaker;

  /// 確定した文の一覧（古い順）。
  List<String> get finals => List.unmodifiable(_finals);

  /// 確定した各文を話し始めた時刻（録音開始からの秒数）。finals と同じ順。
  List<double?> get starts => List.unmodifiable(_starts);

  /// まだ確定していない、認識中の文。
  String get interim => _interim;

  /// 確定した文をすべてつないだ全文。
  String get finalText => _finals.join('\n');

  /// 認識中の文も含めた、画面表示用の全文。
  String get displayText => _interim.isEmpty
      ? finalText
      : [...?_nonEmpty(finalText), _interim].join('\n');

  void add(String text, {required bool isFinal, int? speaker, double? start}) {
    final cleaned = normalizeJapanese(text);
    if (isFinal) {
      if (cleaned.isNotEmpty) _addFinal(cleaned, speaker, start);
      _interim = '';
      _interimSpeaker = null;
      _interimStart = null;
    } else {
      _interim = cleaned;
      _interimSpeaker = speaker;
      _interimStart = start;
    }
  }

  /// 録音停止時など、認識中の文も確定扱いにする。
  void flushInterim() {
    if (_interim.isNotEmpty) {
      _addFinal(_interim, _interimSpeaker, _interimStart);
    }
    _interim = '';
    _interimSpeaker = null;
    _interimStart = null;
  }

  void _addFinal(String text, int? speaker, double? start) {
    _starts.add(start);
    if (speaker != null && speaker != _lastSpeaker) {
      _finals.add('${speakerLabel(speaker)}：$text');
      _lastSpeaker = speaker;
    } else {
      _finals.add(text);
    }
  }

  /// Deepgram の話者番号（0から）を、画面に出す名前にする。
  static String speakerLabel(int speaker) => '話者${speaker + 1}';

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
