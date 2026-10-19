import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 保存した1回分の講義。
class Lecture {
  final String id;
  final String title;
  final DateTime createdAt;
  final Duration duration;
  final Directory dir;

  Lecture({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.duration,
    required this.dir,
  });

  File get transcriptFile => File('${dir.path}/transcript.txt');
  File get audioFile => File('${dir.path}/audio.wav');
  File get metaFile => File('${dir.path}/meta.json');

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'durationSeconds': duration.inSeconds,
  };

  static Lecture fromJson(Map<String, dynamic> json, Directory dir) => Lecture(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    duration: Duration(seconds: json['durationSeconds'] as int? ?? 0),
    dir: dir,
  );
}

/// 講義ごとにフォルダを作り、文字起こし・音声・情報を端末内に保存する。
class LectureStore {
  final Directory root;
  LectureStore(this.root);

  static Future<LectureStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/lectures');
    await root.create(recursive: true);
    return LectureStore(root);
  }

  /// 録音を始めるときに、新しい講義のフォルダを作る。
  Future<Lecture> create({required String title, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final id = at.millisecondsSinceEpoch.toString();
    final dir = Directory('${root.path}/$id');
    await dir.create(recursive: true);
    final lecture = Lecture(
      id: id,
      title: title,
      createdAt: at,
      duration: Duration.zero,
      dir: dir,
    );
    await save(lecture, transcript: '');
    return lecture;
  }

  Future<Lecture> save(
    Lecture lecture, {
    required String transcript,
    Duration? duration,
  }) async {
    final updated = Lecture(
      id: lecture.id,
      title: lecture.title,
      createdAt: lecture.createdAt,
      duration: duration ?? lecture.duration,
      dir: lecture.dir,
    );
    await updated.transcriptFile.writeAsString(transcript);
    await updated.metaFile.writeAsString(jsonEncode(updated.toJson()));
    return updated;
  }

  /// 保存済みの講義を新しい順に返す。
  Future<List<Lecture>> list() async {
    final lectures = <Lecture>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final meta = File('${entity.path}/meta.json');
      if (!await meta.exists()) continue;
      try {
        lectures.add(
          Lecture.fromJson(jsonDecode(await meta.readAsString()), entity),
        );
      } on FormatException {
        continue;
      }
    }
    lectures.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return lectures;
  }

  Future<String> readTranscript(Lecture lecture) async =>
      await lecture.transcriptFile.exists()
      ? lecture.transcriptFile.readAsString()
      : '';

  Future<void> delete(Lecture lecture) => lecture.dir.delete(recursive: true);
}
