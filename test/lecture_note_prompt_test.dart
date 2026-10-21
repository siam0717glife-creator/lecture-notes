import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_notes/services/lecture_note_prompt.dart';

void main() {
  test('Claude アプリに渡す文章に、議事録の形・会議名・本文が入る', () {
    final t = LectureNotePrompt.build(title: '定例会', transcript: '予算の話');
    expect(t, contains('【決定事項】'));
    expect(t, contains('【やること】'));
    expect(t, contains('会議名: 定例会'));
    expect(t, contains('<transcript>\n予算の話\n</transcript>'));
  });
}
