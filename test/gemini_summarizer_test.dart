import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_notes/services/gemini_summarizer.dart';

Map<String, dynamic> chunk(
  String text, {
  String? finish,
  bool thought = false,
}) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': text, if (thought) 'thought': true},
        ],
      },
      'finishReason': ?finish,
    },
  ],
};

String sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\r\n\r\n').join();

void main() {
  test('リクエストに指示文と文字起こしが入る', () {
    final r = GeminiSummarizer.buildRequest(title: '線形代数', transcript: '行列の話');
    final system = r['systemInstruction']['parts'][0]['text'] as String;
    final user = r['contents'][0]['parts'][0]['text'] as String;
    expect(system, contains('【要点】'));
    expect(user, contains('講義名: 線形代数'));
    expect(user, contains('<transcript>\n行列の話\n</transcript>'));
  });

  test('接続先は streamGenerateContent の SSE', () {
    final u = GeminiSummarizer.defaultEndpoint('gemini-flash-latest');
    expect(u.host, 'generativelanguage.googleapis.com');
    expect(u.path, '/v1beta/models/gemini-flash-latest:streamGenerateContent');
    expect(u.queryParameters['alt'], 'sse');
  });

  test('本文だけを返し、考え中の部分は返さない', () {
    expect(GeminiSummarizer.handleEvent(chunk('要点')), '要点');
    expect(GeminiSummarizer.handleEvent(chunk('考え中', thought: true)), '');
    expect(GeminiSummarizer.handleEvent({'usageMetadata': {}}), isNull);
  });

  test('断られた・長すぎたときは例外にする', () {
    expect(
      () => GeminiSummarizer.handleEvent({
        'promptFeedback': {'blockReason': 'SAFETY'},
      }),
      throwsA(isA<SummarizeException>()),
    );
    expect(
      () => GeminiSummarizer.handleEvent(chunk('', finish: 'MAX_TOKENS')),
      throwsA(isA<SummarizeException>()),
    );
    expect(GeminiSummarizer.handleEvent(chunk('終わり', finish: 'STOP')), '終わり');
  });

  test('回数切れ（429）を日本語で説明する', () {
    final m = GeminiSummarizer.describeHttpError(
      429,
      '{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}',
    );
    expect(m, contains('無料で使える回数'));
    expect(m, contains('Quota exceeded'));
  });

  group('サーバーとのやり取り', () {
    late HttpServer server;
    final requested = <String>[];
    late String apiKeyHeader;

    setUp(() async {
      requested.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
    tearDown(() => server.close(force: true));

    GeminiSummarizer summarizer() => GeminiSummarizer(
      apiKey: 'test-key',
      endpoint: (model) => Uri.parse(
        'http://127.0.0.1:${server.port}/v1beta/models/$model:streamGenerateContent?alt=sse',
      ),
    );

    test('ストリーミングで届いた本文をつなげて返す', () async {
      server.listen((req) async {
        requested.add(req.uri.path);
        apiKeyHeader = req.headers.value('x-goog-api-key') ?? '';
        await req.drain<void>();
        req.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        req.response.write(
          sse([
            chunk('…', thought: true),
            chunk('【この講義のまとめ】\n'),
            chunk('行列について学んだ。', finish: 'STOP'),
          ]),
        );
        await req.response.close();
      });
      final text =
          (await summarizer().summarize(title: 't', transcript: '本文').toList())
              .join();
      expect(text, '【この講義のまとめ】\n行列について学んだ。');
      expect(apiKeyHeader, 'test-key');
      expect(requested.single, contains('gemini-flash-latest'));
    });

    test('回数切れのときは軽いモデルでやり直す', () async {
      server.listen((req) async {
        requested.add(req.uri.path);
        await req.drain<void>();
        if (req.uri.path.contains(GeminiSummarizer.primaryModel)) {
          req.response.statusCode = 429;
          req.response.write(
            '{"error":{"code":429,"message":"Quota exceeded"}}',
          );
        } else {
          req.response.write(sse([chunk('軽いモデルの要約', finish: 'STOP')]));
        }
        await req.response.close();
      });
      final text =
          (await summarizer().summarize(title: 't', transcript: '本文').toList())
              .join();
      expect(text, '軽いモデルの要約');
      expect(requested, hasLength(2));
      expect(requested.last, contains(GeminiSummarizer.backupModel));
    });

    test('キーが違う（403）ときはやり直さずに知らせる', () async {
      server.listen((req) async {
        requested.add(req.uri.path);
        await req.drain<void>();
        req.response.statusCode = 403;
        req.response.write('{"error":{"code":403,"message":"denied"}}');
        await req.response.close();
      });
      await expectLater(
        summarizer().summarize(title: 't', transcript: '本文').toList(),
        throwsA(
          isA<SummarizeException>().having(
            (e) => e.message,
            'message',
            contains('API キー'),
          ),
        ),
      );
      expect(requested, hasLength(1));
    });
  });
}
