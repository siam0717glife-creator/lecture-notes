import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

/// 音声認識から届いた1件の結果。
class TranscriptEvent {
  final String text;
  final bool isFinal;

  /// 話している人の番号（0から）。わからないときは null。
  final int? speaker;
  const TranscriptEvent(this.text, {required this.isFinal, this.speaker});
}

/// Deepgram のストリーミング音声認識に音声を送り、結果を受け取る。
///
/// 音声は 16kHz・モノラル・16bit PCM で送る。
class DeepgramTranscriber {
  final String apiKey;
  final String model;
  final String language;
  static const sampleRate = 16000;

  IOWebSocketChannel? _channel;
  Completer<void> _closed = Completer<void>();
  final _events = StreamController<TranscriptEvent>.broadcast();

  DeepgramTranscriber({
    required this.apiKey,
    this.model = 'nova-3',
    this.language = 'ja',
  });

  Stream<TranscriptEvent> get events => _events.stream;

  static Uri buildUri({required String model, required String language}) {
    return Uri.https('api.deepgram.com', '/v1/listen', {
      'model': model,
      'language': language,
      'encoding': 'linear16',
      'sample_rate': '$sampleRate',
      'channels': '1',
      'interim_results': 'true',
      'punctuate': 'true',
      'smart_format': 'true',
      'endpointing': '300',
      // 声の違いで話している人を見分ける（話者分離）。
      'diarize': 'true',
    }).replace(scheme: 'wss');
  }

  /// Deepgram の結果メッセージを読み取る。文字が無いものは null。
  static TranscriptEvent? parseMessage(String raw) {
    final Map<String, dynamic> json = jsonDecode(raw);
    if (json['type'] != 'Results') return null;
    final alts = (json['channel']?['alternatives'] as List?) ?? const [];
    if (alts.isEmpty) return null;
    final text = (alts.first['transcript'] as String?)?.trim() ?? '';
    final isFinal = json['is_final'] == true;
    if (text.isEmpty && !isFinal) return null;
    return TranscriptEvent(
      text,
      isFinal: isFinal,
      speaker: mainSpeaker(alts.first['words'] as List?),
    );
  }

  /// 単語ごとの話者番号から、この文で一番多く話している人を選ぶ。
  static int? mainSpeaker(List? words) {
    final counts = <int, int>{};
    for (final w in words ?? const []) {
      final s = w is Map ? w['speaker'] : null;
      if (s is int) counts[s] = (counts[s] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  Future<void> connect() async {
    final channel = IOWebSocketChannel.connect(
      buildUri(model: model, language: language),
      headers: {HttpHeaders.authorizationHeader: 'Token $apiKey'},
    );
    await channel.ready;
    _channel = channel;
    _closed = Completer<void>();
    channel.stream.listen(
      (message) {
        if (message is! String) return;
        final event = parseMessage(message);
        if (event != null) _events.add(event);
      },
      onError: _events.addError,
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
        final code = channel.closeCode;
        if (code != null && code != 1000) {
          _events.addError(
            '音声認識サーバーとの接続が切れました（コード $code ${channel.closeReason ?? ''}）',
          );
        }
      },
    );
  }

  void sendAudio(Uint8List pcm) => _channel?.sink.add(pcm);

  /// 残りの結果を受け取ってから接続を閉じる。
  Future<void> finish() async {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({'type': 'CloseStream'}));
    try {
      // サーバーが最後の結果を送り終えて接続を閉じるのを待つ。
      await _closed.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // 返事が来なくても、こちらから閉じて終わる。
    }
    await channel.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await finish();
    await _events.close();
  }
}
