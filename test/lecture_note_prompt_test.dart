import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_notes/services/lecture_note_prompt.dart';

void main() {
  test('Claude アプリに渡す文章に、指示・講義名・本文が入る', () {
    final t = LectureNotePrompt.build(title: '統計', transcript: '分散の話');
    expect(t, contains('【要点】'));
    expect(t, contains('講義名: 統計'));
    expect(t, contains('<transcript>\n分散の話\n</transcript>'));
  });
}
