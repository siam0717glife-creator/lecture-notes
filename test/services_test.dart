import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_notes/services/deepgram_transcriber.dart';
import 'package:lecture_notes/services/lecture_store.dart';
import 'package:lecture_notes/services/transcript_buffer.dart';
import 'package:lecture_notes/services/wav_writer.dart';

void main() {
  group('normalizeJapanese', () {
    test('日本語の間の空白を消し、英単語の間は残す', () {
      expect(normalizeJapanese('今日 は 線形 代数 の 講義 です'), '今日は線形代数の講義です');
      expect(normalizeJapanese('Hello world です'), 'Hello worldです');
    });
  });

  group('TranscriptBuffer', () {
    test('途中結果は置き換え、確定結果は積み上げる', () {
      final b = TranscriptBuffer();
      b.add('今日 は', isFinal: false);
      b.add('今日 は 晴れ', isFinal: false);
      expect(b.interim, '今日は晴れ');
      expect(b.finals, isEmpty);
      b.add('今日 は 晴れ です。', isFinal: true);
      expect(b.finals, ['今日は晴れです。']);
      expect(b.interim, '');
      b.add('次 に', isFinal: false);
      expect(b.displayText, '今日は晴れです。\n次に');
      b.flushInterim();
      expect(b.finalText, '今日は晴れです。\n次に');
    });

    test('空の確定結果は追加しない', () {
      final b = TranscriptBuffer()..add('', isFinal: true);
      expect(b.finals, isEmpty);
    });
  });

  group('DeepgramTranscriber', () {
    test('接続先URLに日本語とPCMの設定が入る', () {
      final uri = DeepgramTranscriber.buildUri(model: 'nova-3', language: 'ja');
      expect(uri.scheme, 'wss');
      expect(uri.host, 'api.deepgram.com');
      expect(uri.queryParameters['language'], 'ja');
      expect(uri.queryParameters['encoding'], 'linear16');
      expect(uri.queryParameters['sample_rate'], '16000');
      expect(uri.queryParameters['interim_results'], 'true');
    });

    test('結果メッセージを読み取る', () {
      const raw =
          '{"type":"Results","is_final":true,'
          '"channel":{"alternatives":[{"transcript":"こんにちは","confidence":0.9}]}}';
      final e = DeepgramTranscriber.parseMessage(raw)!;
      expect(e.text, 'こんにちは');
      expect(e.isFinal, isTrue);
    });

    test('結果以外や空の途中結果は無視する', () {
      expect(DeepgramTranscriber.parseMessage('{"type":"Metadata"}'), isNull);
      expect(
        DeepgramTranscriber.parseMessage(
          '{"type":"Results","is_final":false,'
          '"channel":{"alternatives":[{"transcript":""}]}}',
        ),
        isNull,
      );
    });
  });

  test('WavWriter は正しいヘッダー付きの WAV を書く', () async {
    final dir = await Directory.systemTemp.createTemp();
    final file = File('${dir.path}/a.wav');
    final w = WavWriter(file);
    await w.open();
    await w.add(Uint8List.fromList(List.filled(320, 1)));
    await w.add(Uint8List.fromList(List.filled(320, 2)));
    await w.close();
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes);
    expect(bytes.length, 44 + 640);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint32(40, Endian.little), 640);
    await dir.delete(recursive: true);
  });

  test('LectureStore で保存・一覧・削除ができる', () async {
    final dir = await Directory.systemTemp.createTemp();
    final store = LectureStore(dir);
    final a = await store.create(title: '線形代数', now: DateTime(2026, 10, 1));
    await store.create(title: '統計学', now: DateTime(2026, 10, 2));
    await store.save(
      a,
      transcript: '行列の話',
      duration: const Duration(minutes: 90),
    );

    final list = await store.list();
    expect(list.map((l) => l.title), ['統計学', '線形代数']);
    expect(list[1].duration, const Duration(minutes: 90));
    expect(await store.readTranscript(list[1]), '行列の話');

    await store.delete(list[0]);
    expect((await store.list()).length, 1);
    await dir.delete(recursive: true);
  });
}
