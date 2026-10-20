import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lecture_note_prompt.dart';

/// Google の Gemini API（無料枠）で、講義の文字起こしを要約する。
///
/// 結果は届いた分から少しずつ返す（ストリーミング）。
class GeminiSummarizer {
  /// 無料枠で使える Flash の最新版を指す別名。
  static const primaryModel = 'gemini-flash-latest';

  /// 無料枠の回数が尽きたときなどに試す、より軽いモデル。
  static const backupModel = 'gemini-3.5-flash-lite';

  static const host = 'generativelanguage.googleapis.com';

  final String apiKey;
  final Uri Function(String model) _endpoint;

  GeminiSummarizer({required this.apiKey, Uri Function(String model)? endpoint})
    : _endpoint = endpoint ?? defaultEndpoint;

  static Uri defaultEndpoint(String model) => Uri.https(
    host,
    '/v1beta/models/$model:streamGenerateContent',
    {'alt': 'sse'},
  );

  static Map<String, dynamic> buildRequest({
    required String title,
    required String transcript,
  }) => {
    'systemInstruction': {
      'parts': [
        {'text': LectureNotePrompt.instructions},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          {'text': LectureNotePrompt.userMessage(title, transcript)},
        ],
      },
    ],
  };

  /// 要約の文章を、届いた分から少しずつ返す。
  ///
  /// 1つ目のモデルが回数制限などで使えないときは、軽いモデルでやり直す。
  Stream<String> summarize({
    required String title,
    required String transcript,
  }) async* {
    // async* の中では yield* のエラーを catch できないので、await for で受け取る。
    try {
      await for (final t in _summarizeWith(primaryModel, title, transcript)) {
        yield t;
      }
    } on _RetryableError {
      try {
        await for (final t in _summarizeWith(backupModel, title, transcript)) {
          yield t;
        }
      } on _RetryableError catch (e) {
        throw SummarizeException(e.message);
      }
    }
  }

  Stream<String> _summarizeWith(
    String model,
    String title,
    String transcript,
  ) async* {
    final client = HttpClient();
    var receivedText = false;
    try {
      final request = await client.postUrl(_endpoint(model));
      request.headers
        ..contentType = ContentType.json
        ..set('x-goog-api-key', apiKey);
      request.add(
        utf8.encode(
          jsonEncode(buildRequest(title: title, transcript: transcript)),
        ),
      );
      final response = await request.close();

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        final message = describeHttpError(response.statusCode, body);
        // 回数制限・混雑・モデルが無いときは、別のモデルで試す価値がある。
        if (const {404, 429, 500, 503}.contains(response.statusCode)) {
          throw _RetryableError(message);
        }
        throw SummarizeException(message);
      }

      final parser = SseParser();
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final event = parser.addLine(line);
        if (event == null) continue;
        final text = handleEvent(event);
        if (text != null && text.isNotEmpty) {
          receivedText = true;
          yield text;
        }
      }
      if (!receivedText) {
        throw const SummarizeException('要約が空でした。もう一度試してください。');
      }
    } on SocketException {
      throw const SummarizeException('インターネットにつながっていないようです。通信を確認してください。');
    } finally {
      client.close();
    }
  }

  /// SSE の1イベントを処理する。表示する文字があれば返す。
  static String? handleEvent(Map<String, dynamic> event) {
    final error = event['error'] as Map<String, dynamic>?;
    if (error != null) {
      throw SummarizeException('要約中にエラーが起きました: ${error['message'] ?? '不明'}');
    }
    final blocked = (event['promptFeedback'] as Map?)?['blockReason'];
    if (blocked != null) {
      throw const SummarizeException('この内容は要約できませんでした（安全上の理由で断られました）。');
    }
    final candidates = event['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final candidate = candidates.first as Map<String, dynamic>;
    final parts = (candidate['content']?['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final part in parts) {
      // 考え中（thought）の部分は表示せず、本文だけを返す。
      if (part is Map && part['thought'] != true && part['text'] is String) {
        buffer.write(part['text']);
      }
    }
    final finish = candidate['finishReason'];
    if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') {
      throw const SummarizeException('この内容は要約できませんでした（安全上の理由で断られました）。');
    }
    if (finish == 'MAX_TOKENS') {
      throw const SummarizeException('要約が長くなりすぎて途中で止まりました。');
    }
    return buffer.toString();
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
      400 when (detail ?? '').contains('API key') =>
        'Gemini の API キーが正しくないようです。設定を確認してください。',
      401 || 403 => 'Gemini の API キーが正しくないか、使えない状態です。設定を確認してください。',
      404 => '要約に使うモデルが見つかりませんでした。',
      429 => '今日の無料で使える回数を使い切ったようです。明日（日本時間の夕方以降）にもう一度試してください。',
      500 || 503 => 'Gemini 側が混み合っています。少し待ってからもう一度試してください。',
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

class _RetryableError implements Exception {
  final String message;
  _RetryableError(this.message);
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
