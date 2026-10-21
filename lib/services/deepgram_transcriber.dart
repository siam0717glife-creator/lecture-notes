import 'dart:async';
import 'dart:collection';
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

  /// 切れている間にためておく音声の上限（16kHz・16bit で約5分）。
  static const maxPendingBytes = sampleRate * 2 * 60 * 5;

  IOWebSocketChannel? _channel;
  Completer<void> _closed = Completer<void>();
  final _events = StreamController<TranscriptEvent>.broadcast();
  final _status = StreamController<bool>.broadcast();
  final _pending = Queue<Uint8List>();
  int _pendingBytes = 0;
  bool _finishing = false;
  bool _reconnecting = false;

  /// テスト用に接続先を差し替えるとき指定する。
  final Uri? endpoint;

  DeepgramTranscriber({
    required this.apiKey,
    this.model = 'nova-3',
    this.language = 'ja',
    this.endpoint,
  });

  Stream<TranscriptEvent> get events => _events.stream;

  /// つながっているか（false: 切れてつなぎ直し中、true: つながり直した）。
  Stream<bool> get connection => _status.stream;

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

  /// 最初の接続。キーの間違いなどで失敗したら例外になる。
  Future<void> connect() async {
    _finishing = false;
    await _open();
  }

  Future<void> _open() async {
    final channel = IOWebSocketChannel.connect(
      endpoint ?? buildUri(model: model, language: language),
      headers: {HttpHeaders.authorizationHeader: 'Token $apiKey'},
      // 電波が切れたことに早く気づけるよう、定期的に相手の応答を確かめる。
      pingInterval: const Duration(seconds: 5),
    );
    await channel.ready;
    if (_finishing && _reconnecting) {
      // つなぎ直している間に録音が終わった。
      await channel.sink.close();
      return;
    }
    _channel = channel;
    _closed = Completer<void>();
    channel.stream.listen(
      (message) {
        if (message is! String) return;
        final event = parseMessage(message);
        if (event != null) _events.add(event);
      },
      onError: (_) {
        // 切断は onDone でまとめて扱う。
      },
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
        if (_channel == channel) _channel = null;
        if (!_finishing) _reconnect();
      },
    );
    // 切れている間にたまった音声を、つながり直した後にまとめて送る。
    while (_pending.isNotEmpty && _channel == channel) {
      channel.sink.add(_pending.removeFirst());
    }
    _pendingBytes = 0;
  }

  /// 通信が切れたら、つながるまで間隔を空けながら何度でもつなぎ直す。
  Future<void> _reconnect() async {
    if (_reconnecting) return;
    _reconnecting = true;
    _setConnected(false);
    var wait = const Duration(seconds: 1);
    while (!_finishing) {
      await Future.delayed(wait);
      if (_finishing) break;
      try {
        await _open();
        _setConnected(true);
        break;
      } catch (_) {
        if (wait < const Duration(seconds: 8)) wait *= 2;
      }
    }
    _reconnecting = false;
  }

  void _setConnected(bool value) {
    if (!_status.isClosed) _status.add(value);
  }

  void sendAudio(Uint8List pcm) {
    final channel = _channel;
    if (channel != null) {
      channel.sink.add(pcm);
      return;
    }
    // つながっていない間は音声をためておく（多すぎる分は古い方から捨てる）。
    _pending.add(pcm);
    _pendingBytes += pcm.length;
    while (_pendingBytes > maxPendingBytes && _pending.isNotEmpty) {
      _pendingBytes -= _pending.removeFirst().length;
    }
  }

  /// 残りの結果を受け取ってから接続を閉じる。
  Future<void> finish() async {
    _finishing = true;
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
    await _status.close();
  }
}
