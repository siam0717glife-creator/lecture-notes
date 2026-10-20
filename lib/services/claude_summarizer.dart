import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Claude API（Messages API）で講義の文字起こしを要約する。
///
/// Dart には公式 SDK が無いので HTTP で直接呼び出し、結果をストリーミングで受け取る。
class ClaudeSummarizer {
  static const model = 'claude-opus-5-5';
  static final defaultEndpoint = Uri.https('api.anthropic.com', '/v1/messages');

  /// 安全確認で断られたときに、Anthropic おすすめの別モデルで自動的にやり直す。
  static const fallbackBeta = 'server-side-fallback-2026-07-01';

  static const systemPrompt = '''
あなたは大学の講義ノートを作る優秀なアシスタントです。
渡されるのは講義を音声認識で文字起こししたテキストです。聞き間違いや言い直しが含まれるので、文脈から正しい内容を推測して整理してください。
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

  final String apiKey;
  final Uri endpoint;

  ClaudeSummarizer({required this.apiKey, Uri? endpoint})
    : endpoint = endpoint ?? defaultEndpoint;

  static Map<String, dynamic> buildRequest({
    required String title,
    required String transcript,
  }) {
    return {
      'model': model,
      'max_tokens': 16000,
      'stream': true,
      'fallbacks': 'default',
      'thinking': {'type': 'adaptive'},
      'output_config': {'effort': 'medium'},
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content':
              '講義名: $title\n\n<transcript>\n$transcript\n</transcript>\n\n'
              'この講義の講義ノートを作ってください。',
        },
      ],
    };
  }

  /// 要約の文章を、届いた分から少しずつ返す。
  Stream<String> summarize({
    required String title,
    required String transcript,
  }) async* {
    final client = HttpClient();
    try {
      final request = await client.postUrl(endpoint);
      request.headers
        ..contentType = ContentType.json
        ..set('x-api-key', apiKey)
        ..set('anthropic-version', '2023-06-01')
        ..set('anthropic-beta', fallbackBeta);
      request.add(
        utf8.encode(
          jsonEncode(buildRequest(title: title, transcript: transcript)),
        ),
      );
      final response = await request.close();

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw SummarizeException(describeHttpError(response.statusCode, body));
      }

      final parser = SseParser();
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final event = parser.addLine(line);
        if (event == null) continue;
        final text = handleEvent(event);
        if (text != null && text.isNotEmpty) yield text;
      }
    } on SocketException {
      throw const SummarizeException('インターネットにつながっていないようです。通信を確認してください。');
    } finally {
      client.close();
    }
  }

  /// SSE の1イベントを処理する。表示する文字があれば返す。
  static String? handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'content_block_delta':
        final delta = event['delta'] as Map<String, dynamic>?;
        // 考え中（thinking）の部分は表示せず、本文（text）だけを返す。
        if (delta?['type'] == 'text_delta') return delta?['text'] as String?;
        return null;
      case 'message_delta':
        final stop = (event['delta'] as Map<String, dynamic>?)?['stop_reason'];
        if (stop == 'refusal') {
          throw const SummarizeException('この内容は要約できませんでした（安全上の理由で断られました）。');
        }
        if (stop == 'max_tokens') {
          throw const SummarizeException('要約が長くなりすぎて途中で止まりました。');
        }
        return null;
      case 'error':
        final error = event['error'] as Map<String, dynamic>?;
        throw SummarizeException(
          '要約中にエラーが起きました: ${error?['message'] ?? error?['type'] ?? '不明'}',
        );
      default:
        return null;
    }
  }

  static String describeHttpError(int status, String body) {
    String? detail;
    try {
      detail =
          (jsonDecode(body) as Map<String, dynamic>)['error']?['message']
              as String?;
    } on FormatException {
      detail = null;
    }
    final hint = switch (status) {
      401 => 'Claude の API キーが正しくないようです。設定を確認してください。',
      402 || 403 => 'Claude API を使う権限か残高が足りないようです。Anthropic の管理画面を確認してください。',
      429 => '短い時間に使いすぎました。少し待ってからもう一度試してください。',
      529 || 500 || 502 || 503 => 'Claude 側が混み合っています。少し待ってからもう一度試してください。',
      _ => '要約に失敗しました（エラー $status）。',
    };
    return detail == null ? hint : '$hint\n（$detail）';
  }
}

class SummarizeException implements Exception {
  final String message;
  const SummarizeException(this.message);
  @override
  String toString() => message;
}

/// Server-Sent Events の行を受け取り、data の JSON がそろったら返す。
class SseParser {
  final _data = StringBuffer();

  Map<String, dynamic>? addLine(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty) return null;
      final raw = _data.toString();
      _data.clear();
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        return null;
      }
    }
    if (line.startsWith('data:')) {
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(line.substring(5).trimLeft());
    }
    return null;
  }
}
