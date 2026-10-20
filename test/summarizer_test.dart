import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_notes/services/claude_summarizer.dart';

String sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

Map<String, dynamic> textDelta(String t) => {
  'type': 'content_block_delta',
  'index': 1,
  'delta': {'type': 'text_delta', 'text': t},
};

void main() {
  test('リクエストに Haiku 5.5・ストリーミングが入る', () {
    final r = ClaudeSummarizer.buildRequest(title: '線形代数', transcript: '行列の話');
    expect(r['model'], 'claude-haiku-5-5');
    expect(r['stream'], isTrue);
    expect(r['output_config'], {'effort': 'medium'});
    final content = (r['messages'] as List).single['content'] as String;
    expect(content, contains('線形代数'));
    expect(content, contains('<transcript>\n行列の話\n</transcript>'));
  });

  test('無料で使うための貼り付け用の文章に指示と本文が入る', () {
    final t = ClaudeSummarizer.buildSharePrompt(
      title: '統計',
      transcript: '分散の話',
    );
    expect(t, contains('【要点】'));
    expect(t, contains('講義名: 統計'));
    expect(t, contains('分散の話'));
  });

  test('SSE の行から JSON を組み立てる', () {
    final p = SseParser();
    expect(p.addLine('event: content_block_delta'), isNull);
    expect(p.addLine('data: {"type":"ping"}'), isNull);
    expect(p.addLine(''), {'type': 'ping'});
    expect(p.addLine(''), isNull);
  });

  test('本文だけを返し、考え中の部分は返さない', () {
    expect(ClaudeSummarizer.handleEvent(textDelta('要点')), '要点');
    expect(
      ClaudeSummarizer.handleEvent({
        'type': 'content_block_delta',
        'delta': {'type': 'thinking_delta', 'thinking': '...'},
      }),
      isNull,
    );
  });

  test('断られた・長すぎた・エラーのときは例外にする', () {
    expect(
      () => ClaudeSummarizer.handleEvent({
        'type': 'message_delta',
        'delta': {'stop_reason': 'refusal'},
      }),
      throwsA(isA<SummarizeException>()),
    );
    expect(
      () => ClaudeSummarizer.handleEvent({
        'type': 'message_delta',
        'delta': {'stop_reason': 'max_tokens'},
      }),
      throwsA(isA<SummarizeException>()),
    );
    expect(
      () => ClaudeSummarizer.handleEvent({
        'type': 'error',
        'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
      }),
      throwsA(isA<SummarizeException>()),
    );
    expect(
      ClaudeSummarizer.handleEvent({
        'type': 'message_delta',
        'delta': {'stop_reason': 'end_turn'},
      }),
      isNull,
    );
  });

  test('HTTP エラーを日本語で説明する', () {
    final m = ClaudeSummarizer.describeHttpError(
      401,
      '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}',
    );
    expect(m, contains('API キー'));
    expect(m, contains('invalid x-api-key'));
  });

  group('サーバーとのやり取り', () {
    late HttpServer server;
    late Map<String, String> headers;
    late Map<String, dynamic> body;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
    tearDown(() => server.close(force: true));

    Uri url() => Uri.parse('http://127.0.0.1:${server.port}/v1/messages');

    test('ストリーミングで届いた本文をつなげて返す', () async {
      server.listen((req) async {
        headers = {
          'x-api-key': req.headers.value('x-api-key') ?? '',
          'anthropic-version': req.headers.value('anthropic-version') ?? '',
        };
        body = jsonDecode(await utf8.decoder.bind(req).join());
        req.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        req.response.write(
          sse([
            {'type': 'message_start', 'message': {}},
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'thinking', 'thinking': ''},
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'thinking_delta', 'thinking': ''},
            },
            textDelta('【この講義のまとめ】\n'),
            textDelta('行列について学んだ。'),
            {
              'type': 'message_delta',
              'delta': {'stop_reason': 'end_turn'},
            },
            {'type': 'message_stop'},
          ]),
        );
        await req.response.close();
      });

      final s = ClaudeSummarizer(apiKey: 'test-key', endpoint: url());
      final text = (await s.summarize(title: 't', transcript: '本文').toList())
          .join();
      expect(text, '【この講義のまとめ】\n行列について学んだ。');
      expect(headers['x-api-key'], 'test-key');
      expect(headers['anthropic-version'], '2023-06-01');
      expect(body['model'], 'claude-haiku-5-5');
    });

    test('401 のときはキーの確認を促す', () async {
      server.listen((req) async {
        await req.drain<void>();
        req.response.statusCode = 401;
        req.response.write(
          '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}',
        );
        await req.response.close();
      });
      final s = ClaudeSummarizer(apiKey: 'bad', endpoint: url());
      expect(
        s.summarize(title: 't', transcript: '本文').toList(),
        throwsA(
          isA<SummarizeException>().having(
            (e) => e.message,
            'message',
            contains('API キー'),
          ),
        ),
      );
    });
  });
}
